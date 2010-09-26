#!/usr/bin/env bash

# override .backuprc for testing
export BACKUPRC=.testbackuprc
export EXCLUDE_FILE=.testbackupexclude

# pull in environment variables, so we can test them
source ./simple-backup.sh

# export variables we want to test
export TAR
export BACKUP_NAME
export MYSQL_USER
export MYSQL_PASSWORD
export REMOTE_USER
export REMOTE_HOST
export REMOTE_ARCHIVE_DIR
export LOCAL_ARCHIVE_DIR
export LOCAL_RETENTION_DAYS
export REMOTE_RETENTION_DAYS
export DIR_TO_BACKUP
export ARCHIVE_DIR_BASE
export ARCHIVE_DIR_NAME
export FULL_DAY_OF_WEEK

ruby simple-backup-test.rb
