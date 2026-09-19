# Overlay Backup

Simple backup automation based on OverlayFS.

Backups are stored on network storage (e.g. Hetzner StorageBox) as _file system images_ (ext4).
Using file system images works around common limitations of network storage.
This also reduces IOPS load on the storage server, as file system metadata is handled client side, improving performance - sometimes significantly.

File system images are loop-back mounted on temporary directories on the host during backup creation.
The images can also be mounted for introspecting backups interactively, and for restore operations.

Backup automation utilises overlay-fs to generate incremental snapshots if requested.
Multiple snapshots can be created; snapshots will only store differences to the previous snapshot.

## Basics

1. `cp example.settings.env settings.env`, edit defaults to your needs, and add network storage information.
  - Most importantly, set `BASENAME` to the desired base name of your backups on the backup storage.
  - You can use multiple settings files for multiple backups and use the `--settings` command line parameter accordingly.
2. The commands:
  - `backup.sh [<stack-name>]` Create new backup from the configuration in `settings.env`.
    If `<stack-name>` is provided, it is an existing backup stack to incrementally add a new snapshot backup to.
  - `restore.sh <stack-name> <dest-dir>` restores a backup to a local folder.
  - `ls.sh` lists all existing backup stacks with allocated and total image file sizes.
  - `mount.sh <stack-name>` mounts a backup stack (base full backup and all incrementals) for browsing.
  - `umount.sh <stack-name>` unmounts it.
  - `squash.sh <stack-name>` squashes all snapshots into one new snapshot, and removes previous snapshopts.
  - `prune.sh <stack-name>` deletes a backup and all dependent incremental snapshots.

### `settings.env`

This config file defines all information on a backup, including
- Base name
- source files and directories
- destination network filesystem
- maximum size of a full backup and a snapshop backup file
- optional pre- and post- backup and restore callbacks
  (e.g. to dump databases of service being backed up, to be included in the backup)

**It is often feasible to maintain multiple settings files, for multiple services.**
The `--settings <file>` command line option, which is supported by all scripts, can be used to determine which setting to use.
The pattern `settings.env*` is ignored by git to prevent accidental check ins of sensitive information.

## Creating backups

Let's create a full backup with base name "myhome" of user `jens`'s home directory.

- first, we edit `settings.env`, and set
  - `BASENAME=myhome`
  - `backup_sources=/home/jens`
  - the netfs configuration (remote server and password)
    - alternatively, uncomment the `mkdir -p ...` line to skip netfs mounting
- Now we can kick off a backup:
  ```bash
  ./backup.sh
  ```

This will

- mount the network storage if it isn't mounted
- create a file `myhome-<TIMESTAMP>` on the network storage
- create an ext4 filesystem inside that file, and loop-back mount the file system in a temporary directory
- copy all files from the home directory to the FS image mount
- unmount the FS image loop-back mount
- if network storage was mounted in step 1, unmount it

In fact, the new backup file will be created at a temporary place on the network storage, and only moved into place when finished successfully.
This prevents "stale" partial backup files and will ensure that we don't mount filesystem images that are currently being written to.


### Create an incremental backup, or "snapshot"

Now that we have a full back-up, we can create snapshots.
Let's assume the name of our full back-up is `myhome-2025-10-19_18-55-20`.
We supply it to the backup script to create an incremental snapshot:
```bash
./backup.sh myhome-2025-10-19_18-55-20
```

This will do the same preparation / cleanup discussed above, but the backup will be incremental:

- create a file system image `myhome-2025-10-19_18-55-20-snapshot-<TIMESTAMP>` on the network storage
- back up _changes_ in the home directory (compared to the state in `myhome-2025-10-19_18-55-20`) to the snapshot

We can continue and create more snapshots using the same command:
```bash
./backup.sh myhome-2025-10-19_18-55-20
```
Note that only the changes to the most recent _snapshot_ are backed up.

## Listing backups, space used, and space remaining

Use `ls.sh` to get a list of available backups.
It supports `--usage`, `--latest`, --base`, and `--nostats` flags (aside `--settings`).

In its simplest form, it will print all backup images:
```bash
 --- File list in backup images directory '/mnt/backup/myhome'

8.1G -rwxr-xr-x 1 root root 10G Sep 1 14:46 myhome-2025-10-19_18-55-20
 55M -rwxr-xr-x 1 root root 1G Sep  2 08:59 myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00
 10M -rwxr-xr-x 1 root root 1G Sep  3 03:04 myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
312M -rwxr-xr-x 1 root root 1G Sep  4 03:03 myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00
```
The listing shows a full backup and 5 incremental snapshots.
Each of the snapshots only stores differences to the previous snapshot.
For example,
`myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00`
only holds the delta to
`myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00`.

In the file listing, the actual size (bytes on disk) comes first.
Then, after ownership and access bits, the logical (max) size of the sparse file.
For disk usage, the first (actual) size is important.

By passing the `--usage` flag, the remote storage's total size, used, and free space are printed.
This may differ from storage space occupied by this particular backup if the storage is used for other purposes too (e.g. multiple backups with different basenames).
```
 --- NETFS usage
Filesystem                           Size  Used Avail Use% Mounted on
//XXXXXX.your-storagebox.de/backup  1.0T  874G  151G  86% /mnt/backup/myhome
```

`--nostats` suppresses size and access output and prints plain file names instead:
```bash
 --- File list in backup images directory '/mnt/backup/myhome'

myhome-2025-10-19_18-55-20
myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00
myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00
```

`--latest` and `--base` further refine what to print.
`--latest` only prints the most recent backup image stack (both base and all snapshots).
`--base` only prints base images.
The flags can be combined to print the name of the most recent base image,
which is handy for passing it to `backup.sh` to generate a new snapshot
backup image.

Lastly, all non-essential output is directed to STDERR; only the file listing goes to STDOUT.
To determine the last full backup name in a script, use
```
./ls.sh --nostats --base --latest 2>/dev/null
```

## Restoring backups

- Use `restore.sh` to restore the latest state of a backup image stack to a local directory:
  ```bash
  ./restore.sh <backup> <destination>
  ```
  `<backup>` is the base name (full-backup image name) of a backup stack, and `destination` is the local destination directory.
- Following our example from above, restore using:
  ```bash
  ./restore.sh myhome-2025-10-19_18-55-20 /home/jens/restored-home
  ```
Note that even though the base name is used, the full stack including the latest snapshot will be restored.

## Accessing snapshots

Automation provides convenience scripts to list backups and to access backed up data.
`mount.sh` mounts a full "backup stack" to access data, `umount.sh` removes the mounts.

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

## Efficiently copying remote file system images

Since images are sparse, their maximum size will often be significantly larger than the allocated size actually used by data.
`ls.sh` can be used to display both.
To efficiently copy these "large" files over the network, a sparse-aware tool should be used.
`rsync` offers this feature through a combination of `--sparse` and `--compress`:
```bash
rsync --inplace --whole-file --sparse  --info=progress2  --compress <source(s)> <dest>
```

E.g. for Hetzner storageBox:
```bash
rsync --inplace -e 'ssh -p23'  --whole-file --sparse  --info=progress2  --compress \
      "<user>@<user>@your-storagebox.de:<base-name>/<file-pattern>*" .
```

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

## Squash intermediate snapshots

`squash.sh` is provided to squash all changes from an image stack into a new snapshot, and remove all previous snapshots.

For example, given the following stack
```
  myhome-2025-10-19_18-55-20
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-20-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-19-22-30-00
  myhome-2025-10-19_18-55-20-snapshot-2025-10-20-10-00-00
```

squashing it via
```bash
./squash.sh myhome-2025-10-19_18-55-20
```

will result in
```
  myhome-2025-10-19_18-55-20
  myhome-2025-10-19_18-55-20-snapshot-2026-02-20-10-00-00
```
(assuming that 2026-02-20 is the current date).

The snapshot `myhome-2025-10-19_18-55-20-snapshot-2026-02-20-10-00-00` will include all changes of the previous 3 snapshots.

**NOTE:** All transient changes (e.g. files created in `...snapshot-2025-10-19-20-30-00` and deleted in `snapshot-2025-10-20-10-00-00` **will be lost**.

## Remove old backups

`prune.sh` is provided to delete old backup images as well as all images that depend on these.
It can be used on base names and snapshots.

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
