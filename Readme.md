# Overlay Backup

Simple backup automation based on OverlayFS.

Backups are stored on network storage (e.g. Hetzner StorageBox) as _file system images_ (ext4).
Using file system images works around common limitations of network storage.
This also reduces IOPS load on the storage server, as file system metadata is handled client side - improving performance.

File system images are loop-back mounted on temporary directories on the host during backup creation.
The images can also be mounted for introspecting backups interactively, and for restore operations.

Backup automation utilises overlay-fs to generate incremental snapshots if requested.
Multiple snapshots can be created; snapshots will only store differences to the previous snapshot.

## Basics

1. `cp example.settings.env settings.env`, edit defaults to your needs, and add network storage information.
2. The commands:
  - `backup.sh <name> [<stack-name>] -- <files...>` Create new backup containing `<files...>`.
    If `<stack-name>` is provided, it is existing backup stack to incrementally add a new backup to.
  - `restore.sh <stack-name> <dest-dir>` restores a backup to a local folder.
  - `ls.sh` lists all existing backup stacks.
  - `mount.sh <stack-name>` mounts a backup stack (base full backup and all incrementals) for browsing.
  - `umount.sh <stack-name>` unmounts it.
  - `prune.sh <stack-name>` deletes a backup and all dependent incremental snapshots.

## Creating backups

Let's create a backup with base name "myhome" of a user's home directory:
```bash
./backup.sh myhome -- ~/
```
Note the `--` delimiter between options to `backup.sh` and path(s) / files we want to back up.

This will

- mount the network storage if it isn't mounted
- create a file `myhome-<TIMESTAMP>` on the network storage
- create an ext4 filesystem inside that file, and loop-back mount the file system in a temporary directory
- copy all files from the home directory to the FS image mount
- unmount the FS image loop-back mount
- if network storage was mounted in step 1, unmount it

In fact, the new backup file will be created at a temporary place on the network storage, and only moved into place when finished successfully.
This prevents "stale" partial backup files and will ensure that we don't mount filesystem images that are currently being written to.

Now that we have a full back-up, we can create snapshots.
Let's assume the name of our full back-up is `myhome-2025-10-19_18-55-20`.
We supply it to the backup script to create an incremental snapshot:
```bash
./backup.sh myhome myhome-2025-10-19_18-55-20 -- ~/
```

This will do the same preparation / cleanup discussed above, but the backup will be incremental:

- create a file system image `myhome-2025-10-19_18-55-20-snapshot-<TIMESTAMP>` on the network storage
- back up _changes_ in the home directory (compared to the state in `myhome-2025-10-19_18-55-20`) to the snapshot

We can continue and create more snapshots using the same command:
```bash
./backup.sh myhome myhome-2025-10-19_18-55-20 -- ~/
```
Note that only the changes to the most recent _snapshot_ are backed up.

After a while, we have a stack of base + snapshots on the network storage, e.g.
```
  myhome-2025-10-19_18-55-20
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00
  ...
```
Each of the snapshots only stores differences to the previous snapshot, e.g. `myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00` only holds the delta to `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00`.

## Restoring backups

Use `restore.sh` to restore the latest state of a backup image stack to a local directory:
```bash
./restore.sh <backup> <destination>
```

`<backup>` is the base name (full-backup image name) of a backup stack, and `destination` is the local destination directory.

Use `ls.sh` to get a list of available backups.

## Accessing snapshots

Automation provides convenience scripts to list backups and to access backed up data.
- `ls.sh` accesses the network share and lists all existing full backups and snapshots.
- `mount.sh` mounts a full "backup stack" to access data, `umount.sh` removes the mounts.

Based on the example above, `ls.sh` will return:
```
  myhome-2025-10-19_18-55-20
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00
```

`mount.sh` takes a "full back-up" name as its argument and will mount the whole image stack, i.e. full backup and all incremental snapshots.
It uses a temporary directory for its mounts.
Let's run it:
```bash
./mount.sh myhome-2025-10-19_18-55-20 deep
[...]
==> MOUNT COMPLETE: Latest 'myhome-2025-10-19_18-55-20' state is now available at '/tmp/backup/image-mounts/myhome-2025-10-19_18-55-20/3/merged'.
Run './umount.sh "myhome-2025-10-19_18-55-20"' to unmount.
```
You can omit the `deep` option if you only need to access the full merged state of the very last snapshot.

The latest state (including all snapshots, i.e. up to `myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00`) can now be accessed in `/tmp/backup/image-mounts/myhome-2025-10-19_18-55-20/3/merged`.
**Note that the mount is strictly read-only so as to prevent introducing accidental changes.**

Additionally, the initial full backup as well as _differences_ to the respective previous state are accessible via subdirectories in `/tmp/backup/image-mounts/myhome-2025-10-19_18-55-20/`.
- `0/data/` contains the original full backup `myhome-2025-10-19_18-55-20`.  `0/merged` is empty as there is nothing to merge.
- `1/merged/` contains the full snapshot state of `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`.
  It is only available if the `deep` option was given.
  - `1/data/` contains _differences_ between full backup and `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`
- `2/merged/` contains the full snapshot state of `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`
  It is only available if the `deep` option was given.
  - `2/data/` contains _differences_ between `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00` and `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`
- `3/merged/` the full state of all snapshots, including the latest.
  - `3/data/` _differences_ between `myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00` and `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`

The incremental snapshot data directories contain files that have been added or modified, and whiteouts (special character devices) for files and directories that have been deleted.

Use 
```
./umount.sh "myhome-2025-10-19_18-55-20"
```
to unmount the stack.

If `mount.sh` mounted the network storage, use
```
./umount.sh --netfs "myhome-2025-10-19_18-55-20"
```
to unmount that, too.

## Directory structure inside of file system images

File system images use a simple directory structure to store backup data (either full or differences).
Loopback-mounted file system images (either using `mount.sh` or manually) contain:
```
 data/           - Backup data. Full data for full backups, new files and white-outs for incremental snapshots.
 .work/          - Internal "work" directory for overlayfs. Only used on "top-level" writable snapshots during backup.
 merged/         - Merged state of a snapshot and all previous data. Only used when image stacks are mounted.
 created-<ts>    - Timestamp of image creation (after data was copied)
 changes.txt     - Changes from the previous snapshot, or full contents of the backup if this is a full backup.
 image-stack.txt - List of all snapshot images and full backup image, including the current. Most recent snapshot comes first.
```

## Removing old directories

`prune.sh` is provided to delete old backup images as well as all images that depend on these.

For example
```bash
./prune.sh myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
```
will remove

* snapshot `myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00`, and
* snapshot `myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00` which depends on it.

```bash
./prune.sh myhome-2025-10-19_18-55-20
```
will remove all snapshots and the full backup.

# Advanced backup configuration: pre- and post-hooks and pre-defined set of backup sources

The scripts support a more advanced set-up where backup and restore call optional hook functions before and after a backup or restore, repectively.
This is handy to e.g. include a database dump in the backup, and restore it after all files have been copied.

A default set of backup sources can be defined this way, too.
This is handy if the backup includes multiple files and directories as it removes the need to specify these on the command line.

These backup sources and hook functions are implemented via `settings.env`; see [`example.settings.env`](example.settings.env) for boilerplate and details on the callbacks.
