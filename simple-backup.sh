#!/bin/bash

##
# A simple script to backup a file system directory and a mysql database.
# 
# Copyright (c) 2010, Marc Schwieterman
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# - Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the name of the author nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
##

if [ ! -f ~/.backuprc ]; then
	echo "You must create .backuprc in your home directory"
	exit 1
fi

source ~/.backuprc

# default values
DIR_TO_BACKUP=${DIR_TO_BACKUP:-$HOME}
LOCAL_RETENTION_DAYS=${LOCAL_RETENTION_DAYS:-30}
REMOTE_RETENTION_DAYS=${REMOTE_RETENTION_DAYS:-$LOCAL_RETENTION_DAYS}
FULL_DAY_OF_WEEK=${FULL_DAY_OF_WEEK:-5}
TIMESTAMP_FORMAT=${TIMESTAMP_FORMAT:-'%Y%m%d.%H%M%S'}
TIMESTAMP=$(date +$TIMESTAMP_FORMAT)
ARCHIVE_DIR_BASE=${ARCHIVE_DIR_BASE:-$HOME}
ARCHIVE_DIR_NAME=${ARCHIVE_DIR_NAME:-backups}
FS_STRING=${FS_STRING:-fs}
MYSQL_STRING=${MYSQL_STRING:-mysql}
TAR=${TAR:-tar}
MYSQLDUMP=${MYSQLDUMP:-mysqldump}
DEREFERENCE=${DEREFERENCE:-0}

# paths and files
ARCHIVE_DIR=$ARCHIVE_DIR_BASE/$ARCHIVE_DIR_NAME
REMOTE_DIR=${REMOTE_DIR:-$ARCHIVE_DIR}
FS_ARCHIVE_FILE_NAME="${BACKUP_NAME}-${FS_STRING}-${TIMESTAMP}.tar.gz"
MYSQL_ARCHIVE_FILE_NAME="${BACKUP_NAME}-${MYSQL_STRING}-${TIMESTAMP}.sql.gz"
EXCLUDE_FILE=~/.donotbackup
INCREMENTAL_FILE=$ARCHIVE_DIR/incremental.snar
FS_ARCHIVE_FILE=$ARCHIVE_DIR/$FS_ARCHIVE_FILE_NAME
MYSQL_ARCHIVE_FILE=$ARCHIVE_DIR/$MYSQL_ARCHIVE_FILE_NAME

# internal values
DAY_OF_WEEK=$(date +%u)

usage() {
	echo "Usage: $(basename $0) [options]"
	echo "  -h      help, this message"
	echo "  -v      verbose output"
	echo "  -p      pretend, don't execute commands"
	echo "  -b      full backup (file system and database)"
	echo "  -s      rsync of backup files to local host"
	echo "  -f      backup of file system"
	echo "  -d      backup of database"
}

validate_env_vars() {
	if [ -z "$BACKUP_NAME" ]; then
		echo "BACKUP_NAME is required"
		exit 1
	fi
	
	if [ -z "$MYSQL_USER" ]; then
		echo "MYSQL_USER is required"
		exit 1
	fi
	
	if [ -z "$MYSQL_PASSWORD" ]; then
		echo "MYSQL_PASSWORD is required"
		exit 1
	fi
	
	if [ -z "$REMOTE_USER" ]; then
		echo "REMOTE_USER is required"
		exit 1
	fi
	
	if [ -z "$REMOTE_HOST" ]; then
		echo "REMOTE_HOST is required"
		exit 1
	fi
	
	if [ -z "$LOCAL_DIR" ]; then
		echo "LOCAL_DIR is required"
		exit 1
	fi
}

print_configuration() {
	if [ "$VERBOSE" ]; then
		echo "DIR_TO_BACKUP: $DIR_TO_BACKUP"
		echo "ARCHIVE_DIR: $ARCHIVE_DIR"
		echo "BACKUP_NAME: $BACKUP_NAME"
		echo "MYSQL_USER: $MYSQL_USER"
		echo "MYSQL_PASSWORD: $MYSQL_PASSWORD"
		echo "FS_ARCHIVE_FILE_NAME: $FS_ARCHIVE_FILE_NAME"
		echo "MYSQL_ARCHIVE_FILE_NAME: $MYSQL_ARCHIVE_FILE_NAME"
		if [ -f "$EXCLUDE_FILE" ]; then
			echo "Excluding:"
			cat $EXCLUDE_FILE
		fi
	fi
}

# Force a full backup if it's currently FULL_DAY_OF_WEEK.
force_full_backup() {
	if [ "$DAY_OF_WEEK" = "$FULL_DAY_OF_WEEK" ]; then
		if [ "$VERBOSE" ]; then
			echo "Removing $INCREMENTAL_FILE to force full backup"
		fi
		if [ ! "$PRETENDING" ]; then
			rm -f $INCREMENTAL_FILE
		fi
	fi
}

# Validate needed directories and create them if needed and possible.
validate_directories() {
	if [ ! -d "$DIR_TO_BACKUP" ]; then
		echo "DIR_TO_BACKUP: ${DIR_TO_BACKUP} does not exist"
		exit 1
	fi 

	if [ ! -d "$ARCHIVE_DIR" ]; then
		echo "Creating backup dir: $ARCHIVE_DIR"
		if [ ! "$PRETENDING" ]; then
			mkdir -p $ARCHIVE_DIR
		fi
	fi
}

# Backup the configured directory to a tarball. The ARCHIVE_DIR is
# excluded, along with any files in the user's ~/.donotbackup file.
# Symbolic links will be resolved to the files they point to if
# DEREFERENCE is 1. A snapshot archive is stored in ARCHIVE_DIR for
# incremental backups. Removing the file will result in a full backup.
backup_filesystem() {
	local exclude_file_arg
	local dereference_arg

	# create --exclude-from if file exists
	if [ -f "$EXCLUDE_FILE" ]; then
		exclude_file_arg="--exclude-from $EXCLUDE_FILE"
	fi

	# create --dereference if option set
	if [ "$DEREFERENCE" -eq 1 ]; then
		if [ "$VERBOSE" ]; then
			echo "Symbolic links will be resolved to target files"
		fi
		dereference_arg="--dereference"
	fi

	# display backup type
	if [ -f "$INCREMENTAL_FILE" ]; then
		echo "Executing partial backup"
	else
		echo "Executing full backup"
	fi

	if [ ! "$PRETENDING" ]; then
		$TAR --create \
			--file $FS_ARCHIVE_FILE \
			--listed-incremental $INCREMENTAL_FILE \
			--exclude $ARCHIVE_DIR \
			$exclude_file_arg \
			$dereference_arg \
			--gzip \
			--directory $DIR_TO_BACKUP \
			.
	fi
}

# Backup all databases that the configured user has access to.
# The user will at a minimum need SELECT and LOCK TABLES privileges.
backup_database() {
	echo "Dumping mysql databases"
	if [ ! "$PRETENDING" ]; then
		$MYSQLDUMP --all-databases -u$MYSQL_USER -p$MYSQL_PASSWORD | \
			gzip > $MYSQL_ARCHIVE_FILE
	fi
}

# Remove any backup files that are older than REMOTE_RETENTION_DAYS.
remove_old_backups() {
	local archive_dir=$1
	local retention_days=$2
	echo "Removing files older than $retention_days days from $archive_dir"
	if [ ! "$PRETENDING" ]; then
		find $archive_dir -name *.gz -mtime +${retention_days} -exec rm -v {} \;
	elif [ -d "$archive_dir" ]; then
		find $archive_dir -name *.gz -mtime +${retention_days}
	fi
}

# Sync files from remote host to local directory. Requires key-based
# ssh authentication.
sync_files() {
	if [ ! "$PRETENDING" ]; then
		# set the environment up so we don't have to type our passphrase
		eval $(ssh-agent)
	else
		local list_only_arg="--list-only"
	fi

	if [ "$VERBOSE" ]; then
		local verbose_arg="--verbose"
	fi
	
	rsync \
		--archive \
		--compress \
		--rsh=ssh \
		$list_only_arg \
		$verbose_arg \
		$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/ $LOCAL_DIR
}

#
# main script
#

# process command line args
while getopts ":hvpbfds" options; do
	case $options in
		h)
			usage
			exit 0
			;;
		v)
			VERBOSE=1
			;;
		p)
			PRETENDING=1
			;;
		b)
			DO_FS_BACKUP=1
			DO_DB_BACKUP=1
			DO_BACKUP=1
			;;
		f)
			DO_FS_BACKUP=1
			DO_BACKUP=1
			;;
		d)
			DO_DB_BACKUP=1
			DO_BACKUP=1
			;;
		s)
			DO_SYNC=1
			;;
		*)
			echo "unknown option: $OPTARG"
			usage
			exit 1
			;;
	esac
done

print_configuration

if [ "$DO_BACKUP" ]; then
	validate_env_vars
	validate_directories

	echo "Initiating backup at $(date)"
	
	if [ "$PRETENDING" ]; then
		echo "Running in pretend mode. No commands will actually be executed."
	fi
	
	if [ "$DO_FS_BACKUP" ]; then
		force_full_backup
		backup_filesystem
	fi
	
	if [ "$DO_DB_BACKUP" ]; then
		backup_database
	fi
	
	remove_old_backups $ARCHIVE_DIR $REMOTE_RETENTION_DAYS
	
	echo "Backup completed at $(date)"
	exit 0
fi

if [ "$DO_SYNC" ]; then
	sync_files
	remove_old_backups $LOCAL_DIR $LOCAL_RETENTION_DAYS
	exit 0
fi

usage

