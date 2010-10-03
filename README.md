# Simple Backup

by Marc Schwieterman - http://marcschwieterman.com/

## Overview

Simple Backup is a bash script that will backup a single file system directory and a mysql database. It is intended to be used for personal web sites, hosting smaller amounts of data. You can run the script out of cron on the server that hosts your website, and it is recommended that you also run a sync process on your personal computer to ensure you have a copy of your backup files that is not on the server.

The default options will remove backup files after they are 30 days old. File system backups are done via tar, with a full backup once a week and incremental backups for all other days. The database backup dumps all tables the configured account has access to.

## Requirements

*   Bash
*   GNU tar or some variant on the server
*   SSH access to the server

    GitHub has a good [guide](http://help.github.com/key-setup-redirect), just copy your public key into your ~/.ssh/authorized_keys files on the server.

*   rsync on the local system
*   scp on the local system
*   growlnotify on the local system (optional)

## Installation

To install, simply copy the script to your local ~/bin directory and create a ~/.backuprc file.

### Configuration

Use the *-c* option to display the more important configuration variables.

    simple-backup.sh -c

### Upload

You can upload both the simple-backup.sh script and your .backuprc file from your local system to the configured server with the *-u* option.

    simple-backup.sh -u

## Usage

Backup operations are intended to be run out of cron. Ideally you want your backups to run once a day, with the supporting processes running more frequently. The following cron entries will result in your backup running once a day at midnight, with the local sync running at 15 after the hour and notifications being sent at 30 minutes past the hour. You can set up cron entries with *crontab -e*.

### Server Cron Entry

    0 0 * * * /home/username/bin/simple-backup.sh -b >> /home/username/backups/backup.log 2>&1

### Local Cron Entries

    15 * * * * /home/username/bin/simple-backup.sh -s >> /home/username/backups/rsync.log 2>&1
    30 * * * * /home/username/bin/simple-backup.sh -n >> /home/username/backups/notify.log 2>&1
 

