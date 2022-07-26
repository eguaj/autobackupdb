backupdb.sh
===========

Automatically dump postgresql and mysql databases for backup.

Supported databases:
- postgresql
- mysql
- mongo

Also:
- Backup list of installed packages (`dpkg -l`, `yum list installed`, `rpm -ql`).
- Execute optional `/usr/local/bin/local-backup` script to trigger additional
  backup actions.
- Backup apt-keys.
- Backup Docker images.
