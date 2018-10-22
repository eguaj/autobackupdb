#!/bin/bash

BACKUP_DIR="/var/backupdb"

shopt -s nullglob
set -o pipefail

function backup_dpkg_list {
	dpkg -l > "${BACKUP_DIR}/dpkg.list"
}

function backup_pg {
	which pg_dump > /dev/null
	if [ $? -ne 0 ]; then
		return 0
	fi
	local DB_LIST=( $(su postgres -c "psql -tA -c \"SELECT datname FROM pg_database WHERE datname "'!'"~ E'(template|bench)'\"") )
	if [ $? -ne 0 ]; then
		printf "Error: could not list PostgreSQL's databases!\n"
		return 1
	fi
	local GLOBAL_RET=0
	for DBNAME in "${DB_LIST[@]}"; do
		printf "* Dumping pgsql '%s'... " "${DBNAME}"
		(
			set -e
			local TMPDB
			TMPDB=$(mktemp "${BACKUP_DIR}/tmp.${DBNAME}.XXXXXX")
			su postgres -c "pg_dump -Fc \"${DBNAME}\"" > "${TMPDB}"
			mv "${TMPDB}" "${BACKUP_DIR}/pgsql.${DBNAME}.pg_dump.Fc"
		)
		if [ $? -ne 0 ]; then
			printf "Error: backup error on database '%s'!" "${DBNAME}"
			GLOBAL_RET=1
		else
			printf "Done.\n"
		fi
	done
	return $GLOBAL_RET
}

function backup_mysql {
	which mysql > /dev/null
	if [ $? -ne 0 ]; then
		return 0
	fi
	local DB_LIST=( $(mysql -Bse 'show databases') )
	if [ $? -ne 0 ]; then
		printf "Error: could not list MySQL's databases!\n"
		return 1
	fi
	local GLOBAL_RET=0
	for DBNAME in "${DB_LIST[@]}"; do
		if [ "${DBNAME}" = "information_schema" -o "${DBNAME}" = "performance_schema" ]; then
			continue
		fi

		printf "* Dumping mysql '%s'... " "${DBNAME}"
		(
			set -e
			local TMPDB
			TMPDB=$(mktemp "${BACKUP_DIR}/tmp.${DBNAME}.XXXXXX")
			mysqldump "${DBNAME}" | gzip > "${TMPDB}"
			mv "${TMPDB}" "${BACKUP_DIR}/mysql.${DBNAME}.dump.gz"
		)
		if [ $? -ne 0 ]; then
			printf "Error: backup error on database '%s'!" "${DBNAME}"
			GLOBAL_RET=1
		else
			printf "Done.\n"
		fi
	done
	return $GLOBAL_RET
}

function backup_mongo {
	which mongo > /dev/null
	if [ $? -ne 0 ]; then
		return 0
	fi
	local DB_LIST
	DB_LIST=( $(mongo --quiet --eval  "printjson(db.adminCommand('listDatabases'))" | php -r '$r=json_decode(file_get_contents("php://stdin"),true);foreach($r["databases"]as$d){printf("%s\n",$d["name"]);};') )
	if [ $? -ne 0 ]; then
		printf "Error: could not list Mongo's databases!\n"
		return 1
	fi
	local GLOBAL_RET=0
	for DBNAME in "${DB_LIST[@]}"; do
		printf "* Dumping mongo '%s'... " "${DBNAME}"
		(
			set -e
			local TMPDB
			TMPDB=$(mktemp -d "${BACKUP_DIR}/mongo.${DBNAME}.db.XXXXXX")
			mongodump -o "${TMPDB}" -d "${DBNAME}"
			rm -Rf "${BACKUP_DIR}/mongo.$DBNAME.db"
			mv "${TMPDB}" "${BACKUP_DIR}/mongo.${DBNAME}.db"
		)
		if [ $? -ne 0 ]; then
			printf "Error: backup error on database '%s'!" "${DBNAME}"
			GLOBAL_RET=1
		else
			printf "Done.\n"
		fi
	done
	return $GLOBAL_RET
}

function backup_local {
	local GLOBAL_RET=0
	if [ -x "/usr/local/bin/local-backup" ]; then
		printf "* Running local-backup... "
		/usr/local/bin/local-backup backup
		if [ $? -ne 0 ]; then
			printf "Error: local-backup failed!\n"
			GLOBAL_RET=1
		else
			printf "Done.\n"
		fi
	fi
	return $GLOBAL_RET
}

function main {
	local RET=0

	cd "${BACKUP_DIR}"
	if [ $? -ne 0 ]; then
		printf "Error: could not chdir to '%s'\n" "${BACKUP_DIR}"
		return 1
	fi


	backup_dpkg_list
	(( RET = RET || $? ))

	backup_pg
	(( RET = RET || $? ))

	backup_mysql
	(( RET = RET || $? ))

	backup_mongo
	(( RET = RET || $? ))

	backup_local
	(( RET = RET || $? ))

	if [ $RET -ne 0 ]; then
		printf "Error: some operations failed! Backup might not be consistent!\n"
	fi
	return $RET
}

main "$@"

# shellcheck disable=SC2016
