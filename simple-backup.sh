#!/bin/bash

##
# A simple script to backup a file system directory and a mysql database.
## 
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

BACKUPRC=${BACKUPRC:-~/.backuprc}
if [ ! -f "$BACKUPRC" ]; then
    echo "You must create .backuprc in your home directory"
    exit 1
fi

source $BACKUPRC

# programs
TAR=${TAR:-tar}
MYSQLDUMP=${MYSQLDUMP:-mysqldump}
RSYNC=${RSYNC:-rsync}
SCP=${SCP:-scp}

# names and formatting
SCRIPT_NAME=simple-backup.sh
FS_STRING=${FS_STRING:-fs}
MYSQL_STRING=${MYSQL_STRING:-mysql}
TIMESTAMP_FORMAT=${TIMESTAMP_FORMAT:-'%Y%m%d.%H%M%S'}
TIMESTAMP=${TIMESTAMP:-$(date +$TIMESTAMP_FORMAT)}
ARCHIVE_DIR_NAME=${ARCHIVE_DIR_NAME:-backups}
FS_ARCHIVE_FILE_NAME="${BACKUP_NAME}-${FS_STRING}-${TIMESTAMP}.tar.gz"
MYSQL_ARCHIVE_FILE_NAME="${BACKUP_NAME}-${MYSQL_STRING}-${TIMESTAMP}.sql.gz"

# options
FULL_DAY_OF_WEEK=${FULL_DAY_OF_WEEK:-5} # Friday

# retention policies
REMOTE_RETENTION_DAYS=${REMOTE_RETENTION_DAYS:-30}
LOCAL_RETENTION_DAYS=${LOCAL_RETENTION_DAYS:-30}

# remote paths and files
REMOTE_HOME=${REMOTE_HOME:-$HOME}
REMOTE_BIN=${REMOTE_BIN:-$REMOTE_HOME/bin}
REMOTE_SCRIPT_FILE=$REMOTE_BIN/$SCRIPT_NAME
REMOTE_ARCHIVE_DIR=${REMOTE_ARCHIVE_DIR:-$REMOTE_HOME/$ARCHIVE_DIR_NAME}
DIR_TO_BACKUP=${DIR_TO_BACKUP:-$REMOTE_HOME}
INCREMENTAL_FILE=$REMOTE_ARCHIVE_DIR/incremental.snar
FS_ARCHIVE_FILE=$REMOTE_ARCHIVE_DIR/$FS_ARCHIVE_FILE_NAME
EXCLUDE_FILE=${EXCLUDE_FILE:-~/.backupexcludes}
MYSQL_ARCHIVE_FILE=$REMOTE_ARCHIVE_DIR/$MYSQL_ARCHIVE_FILE_NAME
LAST_BACKUP_FILE=$REMOTE_ARCHIVE_DIR/last_backup

# local paths and files
LOCAL_HOME=${LOCAL_HOME:-$HOME}
LOCAL_BIN=${LOCAL_BIN:-$LOCAL_HOME/bin}
LOCAL_SCRIPT_FILE=$LOCAL_BIN/$SCRIPT_NAME
LOCAL_ARCHIVE_DIR=${LOCAL_ARCHIVE_DIR:-$LOCAL_HOME/$ARCHIVE_DIR_NAME}

# internal values
DAY_OF_WEEK=$(date +%u)

usage() {
    echo "Usage: $(basename $0) [options]"
    echo ""
    echo "General options:"
    echo ""
    echo "  -h      help, this message"
    echo "  -c      print configuration"
    echo "  -v      verbose output"
    echo "  -p      pretend, don't execute commands"
    echo ""
    echo "Backup options:"
    echo ""
    echo "  -u      upload script files to remote host"
    echo "  -b      backup both file system and database"
    echo "  -f      backup file system"
    echo "  -d      backup database"
    echo "  -o      force full file system backup"
    echo ""
    echo "Sync options:"
    echo ""
    echo "  -s      rsync backup files to local host"
    echo ""
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
}

print_configuration() {
    echo "DIR_TO_BACKUP: $DIR_TO_BACKUP"
    echo "REMOTE_ARCHIVE_DIR: $REMOTE_ARCHIVE_DIR"
    echo "BACKUP_NAME: $BACKUP_NAME"
    echo "MYSQL_USER: $MYSQL_USER"
    echo "MYSQL_PASSWORD: $MYSQL_PASSWORD"
    echo "FS_ARCHIVE_FILE_NAME: $FS_ARCHIVE_FILE_NAME"
    echo "MYSQL_ARCHIVE_FILE_NAME: $MYSQL_ARCHIVE_FILE_NAME"
    if [ -f "$EXCLUDE_FILE" ]; then
        echo "Excluding:"
        cat $EXCLUDE_FILE
    fi
}

# Force a full backup if it's currently FULL_DAY_OF_WEEK.
force_full_backup_if_needed() {
    if [ "$DAY_OF_WEEK" = "$FULL_DAY_OF_WEEK" -o "$DO_FORCE_FULL" ]; then
        if [ "$VERBOSE" ]; then
            echo "Removing $INCREMENTAL_FILE to force full backup"
        fi
        if [ ! "$PRETENDING" ]; then
            rm -f $INCREMENTAL_FILE
        fi
    fi
}

# Validate needed directories and create them if needed and possible.
# Will not create nested directories, so the REMOTE_ARCHIVE_DIR must reside
# in an existing directory, or it will need to be created manually.
validate_directories() {
    if [ ! -d "$DIR_TO_BACKUP" ]; then
        echo "DIR_TO_BACKUP: ${DIR_TO_BACKUP} does not exist"
        exit 1
    fi 

    if [ ! -d "$REMOTE_ARCHIVE_DIR" ]; then
        echo "Creating backup dir: $REMOTE_ARCHIVE_DIR"
        if [ ! "$PRETENDING" ]; then
            mkdir $REMOTE_ARCHIVE_DIR
        fi
    fi
}

# Backup the configured directory to a tarball. The REMOTE_ARCHIVE_DIR is
# excluded, along with any files in the user's EXCLUDE_FILE file.
# A snapshot archive is stored in REMOTE_ARCHIVE_DIR for
# incremental backups. Removing the file will result in a full backup.
backup_file_system() {
    local exclude_file_arg

    force_full_backup_if_needed

    # create --exclude-from if file exists
    if [ -f "$EXCLUDE_FILE" ]; then
        exclude_file_arg="--exclude-from $EXCLUDE_FILE"
    fi

    # display backup type
    if [ "$DO_FORCE_FULL" -o ! -f "$INCREMENTAL_FILE" ]; then
        echo "Executing full backup"
    else
        echo "Executing partial backup"
    fi

    if [ ! "$PRETENDING" ]; then
        $TAR --create \
            --file $FS_ARCHIVE_FILE \
            --listed-incremental $INCREMENTAL_FILE \
            --exclude $(basename $REMOTE_ARCHIVE_DIR) \
            $exclude_file_arg \
            --gzip \
            --directory $(dirname $DIR_TO_BACKUP) \
            $(basename $DIR_TO_BACKUP)
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
        find $archive_dir -name \*.gz -mtime +${retention_days} -exec rm -v {} \;
    elif [ -d "$archive_dir" ]; then
        find $archive_dir -name \*.gz -mtime +${retention_days}
    fi
}

# Sync files from remote host to local directory. Requires key-based
# ssh authentication.
sync_files() {
    if [ "$PRETENDING" ]; then
        local list_only_arg="--list-only"
    fi

    if [ "$VERBOSE" ]; then
        local verbose_arg="--verbose"
    fi
    
    $RSYNC \
        --archive \
        --compress \
        --rsh=ssh \
        $list_only_arg \
        $verbose_arg \
        $REMOTE_USER@$REMOTE_HOST:$REMOTE_ARCHIVE_DIR/ $LOCAL_ARCHIVE_DIR
}

deploy() {
    local local_backuprc=$LOCAL_HOME/.backuprc
    local remote_backuprc=$REMOTE_HOME/.backuprc
    local local_backupexclude=$LOCAL_HOME/.backupexclude
    local remote_backupexclude=$REMOTE_HOME/.backupexclude
    if [ "$PRETENDING" ]; then
        echo "Running in pretend mode."
        echo "deploying $local_backuprc to $remote_backuprc"
        echo "deploying $local_backupexclude to $remote_backupexclude"
        echo "deploying $LOCAL_SCRIPT_FILE to $REMOTE_SCRIPT_FILE"
    else
        $SCP $local_backuprc $REMOTE_USER@$REMOTE_HOST:$remote_backuprc
        if [ -f "$local_backupexclude" ]; then
            $SCP $local_backupexclude $REMOTE_USER@$REMOTE_HOST:$remote_backupexclude
        fi
        $SCP $LOCAL_SCRIPT_FILE $REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT_FILE
    fi
}

#
# main script
#

# process command line args
while getopts ":hcvpbfodsu" options; do
    case $options in
        h)
            usage
            exit 0
            ;;
        c)
            DO_PRINT_CONFIG=1
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
        o)
            DO_FORCE_FULL=1
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
        u)
            DO_DEPLOY=1
            ;;
        *)
            echo "unknown option: $OPTARG"
            usage
            exit 1
            ;;
    esac
done

if [ "$DO_PRINT_CONFIG" ]; then
    print_configuration
    exit 0
fi

if [ "$DO_DEPLOY" ]; then
    deploy
    exit 0
fi

if [ "$DO_BACKUP" -a "$DO_SYNC" ]; then
    echo "Backup and sync options are mutually exclusive"
    usage
    exit 1
fi

if [ "$DO_BACKUP" ]; then
    validate_env_vars
    validate_directories

    echo "Initiating backup at $(date)"
    
    if [ "$PRETENDING" ]; then
        echo "Running in pretend mode. No commands will actually be executed."
    fi
    
    if [ "$DO_FS_BACKUP" ]; then
        backup_file_system
    fi
    
    if [ "$DO_DB_BACKUP" ]; then
        backup_database
    fi
    
    remove_old_backups $REMOTE_ARCHIVE_DIR $REMOTE_RETENTION_DAYS

    echo $TIMESTAMP > $LAST_BACKUP_FILE
    
    echo "Backup completed at $(date)"
    exit 0
fi

if [ "$DO_SYNC" ]; then
    sync_files
    remove_old_backups $LOCAL_ARCHIVE_DIR $LOCAL_RETENTION_DAYS
    exit 0
fi

# prevent usage from running when sourced
if [ $(basename "$0") = "$SCRIPT_NAME" ]; then
    usage
fi

