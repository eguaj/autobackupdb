#!/bin/bash

# shellcheck disable=SC2181

BACKUP_DIR="/var/backupdb"

shopt -s nullglob
set -o pipefail

function usage {
	cat <<EOF
Usage
-----

  $0 [options]

Options
-------

  --no-backup-apt-keys
  --no-backup-pkg-list
  --no-backup-pg
  --no-backup-mysql
  --no-backup-mongo
  --no-backup-docker-images
  --no-backup-local

EOF
}

function backup_dpkg_list {
	dpkg -l > "${BACKUP_DIR}/dpkg.list"
}

function backup_rpm_list {
	rpm -qa | sort > "${BACKUP_DIR}/rpm.list"
}

function backup_yum_list {
	yum list installed --quiet > "${BACKUP_DIR}/yum.list"
}

function backup_apt_keys {
	if [ -v "${NO_BACKUP_APT_KEYS}" ]; then
		return 0
	fi
	if command -v apt-key > /dev/null; then
		apt-key exportall > "${BACKUP_DIR}/apt.keys"
	fi
}

function backup_pkg_list {
	if [ -v "${NO_BACKUP_PKG_LIST}" ]; then
		return 0
	fi
	if command -v dpkg > /dev/null; then
		backup_dpkg_list
	elif command -v yum > /dev/null; then
		backup_yum_list
	elif command -v rpm > /dev/null; then
		backup_rpm_list
	fi
}

function backup_pg {
	if [ -v "${NO_BACKUP_PG}" ]; then
		return 0
	fi
	if ! command -v pg_dump > /dev/null; then
		return 0
	fi
	local DB_LIST
	mapfile -t DB_LIST < <(su postgres -c "psql -tA -c \"SELECT datname FROM pg_database WHERE datname "'!'"~ E'(template|bench)'\"")
	if [ $? -ne 0 ]; then
		printf "Error: could not list PostgreSQL's databases!\n"
		return 1
	fi
	local GLOBAL_RET=0
	printf "* Dumping pgsql schemas... "
	(
		set -e
		local TMPDB
		TMPDB=$(mktemp "${BACKUP_DIR}/tmp.schema-only.XXXXXX")
		su postgres -c "pg_dumpall --schema-only" | gzip > "${TMPDB}"
		mv "${TMPDB}" "${BACKUP_DIR}/pgsql.schema-only.sql.gz"
	)
	if [ $? -ne 0 ]; then
		printf "Error: schema-only dump error!"
		GLOBAL_RET=1
	else
		printf "Done.\n"
	fi
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
	if [ -v "${NO_BACKUP_MYSQL}" ]; then
		return 0
	fi
	if ! command -v mysql > /dev/null; then
		return 0
	fi
	local DB_LIST
	mapfile -t DB_LIST < <(mysql -Bse 'show databases')
	if [ $? -ne 0 ]; then
		printf "Error: could not list MySQL's databases!\n"
		return 1
	fi
	local GLOBAL_RET=0
	for DBNAME in "${DB_LIST[@]}"; do
		if [ "${DBNAME}" = "information_schema" ] || [ "${DBNAME}" = "performance_schema" ]; then
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
	if [ -v "${NO_BACKUP_MONGO}" ]; then
		return 0
	fi
	if ! command -v mongosh > /dev/null; then
		return 0
	fi
	local DB_LIST
	# shellcheck disable=SC2016
	mapfile -t DB_LIST < <(mongosh --quiet --eval  "EJSON.stringify(db.adminCommand('listDatabases'))" | php -r '$r=json_decode(file_get_contents("php://stdin"),true);foreach($r["databases"]as$d){printf("%s\n",$d["name"]);};')
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

function backup_docker_images {
	if [ -v "${NO_BACKUP_DOCKER_IMAGES}" ]; then
		return 0
	fi
	if ! command -v docker > /dev/null; then
		return 0
	fi
	local IMAGE_LIST
	mapfile -t IMAGE_LIST < <(docker images --format="{{.Repository}}:{{.Tag}}")
	if [ $? -ne 0 ]; then
		printf "Error: could not list docker images!\n"
		return 1
	fi
	local GLOBAL_RET=0
	local IMAGE
	local IMAGE_FNAME
	for IMAGE in "${IMAGE_LIST[@]}"; do
		IMAGE_FNAME=$(echo "${IMAGE}" | sed 's:%:%25:g;s:/:%2f:g')
		printf "* Saving docker image '%s'... " "${IMAGE}"
		(
			set -e
			docker save "${IMAGE}" | gzip > "${BACKUP_DIR}/docker-image.${IMAGE_FNAME}.tar.gz"
		)
		if [ $? -ne 0 ]; then
			printf "Error: docker save error on image '%s'!" "${IMAGE}"
			GLOBAL_RET=1
		else
			printf "Done.\n"
		fi
	done
	return $GLOBAL_RET
}

function backup_local {
	if [ -v "${NO_BACKUP_LOCAL}" ]; then
		return 0
	fi
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

	while [ $# -gt 0 ]; do
		case "$1" in
			--help|-h)
				shift
				usage
				exit 0
				;;
			--no-backup-apt-keys)
				shift
				NO_BACKUP_APT_KEYS=1
				;;
			--no-backup-pkg-list)
				shift
				NO_BACKUP_PKG_LIST=1
				;;
			--no-backup-pg)
				shift
				NO_BACKUP_PG=1
				;;
			--no-backup-mysql)
				shift
				NO_BACKUP_MYSQL=1
				;;
			--no-backup-mongo)
				shift
				NO_BACKUP_MONGO=1
				;;
			--no-backup-docker-images)
				shift
				NO_BACKUP_DOCKER_IMAGES=1
				;;
			--no-backup-local)
				NO_BACKUP_LOCAL=1
				;;
			--)
				shift
				break
				;;
			*)
				echo "Error: unknown option '$1'!" 1>&2
				exit 1
				;;
		esac
	done

	cd "${BACKUP_DIR}"
	if [ $? -ne 0 ]; then
		printf "Error: could not chdir to '%s'\n" "${BACKUP_DIR}"
		return 1
	fi

	if [ -z "${GZIP}" ]; then
		export GZIP="--rsyncable"
	fi

	backup_apt_keys
	(( RET = RET || $? ))

	backup_pkg_list
	(( RET = RET || $? ))

	backup_pg
	(( RET = RET || $? ))

	backup_mysql
	(( RET = RET || $? ))

	backup_mongo
	(( RET = RET || $? ))

	backup_docker_images
	(( RET = RET || $? ))

	backup_local
	(( RET = RET || $? ))

	if [ $RET -ne 0 ]; then
		printf "Error: some operations failed! Backup might not be consistent!\n"
	fi
	return $RET
}

main "$@"

