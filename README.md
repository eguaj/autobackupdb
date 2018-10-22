backupdb.sh
===========

Automatically dump postgresql and mysql databases for backup.

Supported databases:
- postgresql
- mysql
- mongo

Also:
- Backup list of installed packages (`dpkg -l`) to `${BACKUP_DIR}/dpkg.list`.
- Execute optional `/usr/local/bin/local-backup` script to trigger additional
  backup actions.
