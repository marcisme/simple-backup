# Simple Backup

by Marc Schwieterman - http://marcschwieterman.com/

## Overview

Simple Backup is a bash script that will backup a single file system directory and a mysql database. It is intended to be used for personal web sites, hosting smaller amounts of data. You can run the script out of cron on the server that hosts your website, and it is recommended that you also run a sync process on your personal computer to ensure you have a copy of your backup files that is not on the server.

The default options will remove backup files after they are 30 days old. File system backups are done via tar, with a full backup once a week and incremental backups for all other days. The database backup dumps all tables the configured account has access to. You should set up a read only mysql user just for backups.

This script is a result of my personal desire to back up my blog, and it is based on my post about [backing up your personal website](http://marcschwieterman.com/blog/backing-up-your-personal-website/). I didn't see much else out there, so hopefully this is useful for others as well. I'm happy to fix any bugs that may be encountered, but I can't guarantee any kind of timeline. I accept absolutely no responsibility for the integrity of backups created with this script, and I highly recommend doing a test recovery if you choose to use it.

## System Requirements

*   Bash
*   GNU tar or some variant on the server
*   SSH access to the server

    GitHub has a good [guide](http://help.github.com/key-setup-redirect), just copy your public key into your ~/.ssh/authorized_keys files on the server.

*   rsync on the local system
*   scp on the local system
*   growlnotify on the local system (optional)

The script has only been tested on Linux and OS X, but it will probably work on Cygwin.

## Installation

To install, simply copy the simple-backup.sh script to your local ~/bin directory and create a ~/.backuprc file based on the backuprc.example found here.

### Configuration

Use the *-c* option to display the more important configuration variables.

    simple-backup.sh -c

### Upload

You can upload both the simple-backup.sh script and your .backuprc file from your local system to the configured server with the *-u* option.

    simple-backup.sh -u

## Usage

Backup operations are intended to be run out of cron. Ideally you want your backups to run once a day, with the supporting processes running more frequently. The following cron entries will result in your backup running once a day at midnight, with the local sync running at 15 after the hour and notifications being sent at 30 minutes past the hour. You can set up cron entries with *crontab -e*.

### Server Cron Entry

Backup both the file system and the database.

    0 0 * * * /home/username/bin/simple-backup.sh -b >> /home/username/backups/backup.log 2>&1

### Local Cron Entries

Run a sync shortly after backups. This is done hourly in case something happens the first time. Notify if a successfuly backup hasn't been seen within the last 24 hours.

    15 * * * * /home/username/bin/simple-backup.sh -s >> /home/username/backups/rsync.log 2>&1
    30 * * * * /home/username/bin/simple-backup.sh -n >> /home/username/backups/notify.log 2>&1

## Known Issues

*   In my testing incremental backups were sometimes not so incremental on OS X. I've seen this with hfstar and gnutar, both of which I installed via [macports](http://www.macports.org/). I've yet to see any issues on Linux.
 
## Changelog

*   0.1 initial release

