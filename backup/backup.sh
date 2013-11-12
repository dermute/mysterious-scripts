#!/bin/bash

# This is a simple backup script that uses rsync to backup files and does
# complete mysql table dumps. Note that this script DOES NOT EXPIRE OLD BACKUPS.
# Place it in /etc/cron.daily to execute it automatically. For hourly backups,
# it will need to be placed in /etc/cron.hourly, and the $TODAY / $YESTERDAY
# variables will need to be changed.

TODAY=`date +"%Y%m%d"`
YESTERDAY=`date -d "1 day ago" +"%Y%m%d"`

# Set the path to rsync on the remote server so it runs with sudo.
RSYNC="/usr/bin/sudo /usr/bin/rsync"

# This is a list of files to ignore from backups.
EXCLUDES="excludes"

# Servername
SERVERNAME="$1"

# BACKUP-DIR
BACKDIR=/mnt/backup

# I use a separate volume for backups. Remember that you will not be generating
# backups that are particularly large (other than the initial backup), but that
# you will be creating thousands of hardlinks on disk that will consume inodes.
DESTINATION="/$BACKDIR/$SERVERNAME/$TODAY/"

# Keep database backups in a separate directory.
mkdir -p /$BACKDIR/$SERVERNAME/db

# This command rsync's files from the remote server to the local server.
#
# The "rsync" user is a special user on the remote server that has permissions
# to run a specific rsync command. We limit it so that if the backup server is
# compromised it can't use rsync to overwrite remote files by setting a remote
# destination. I determined the sudo command to allow by running the backup
# with the rsync user granted permission to use any flags for rsync, and then
# copied the actual command run from ps auxww. With these options, under
# Ubuntu, the sudo line is:
#
#   rsync	ALL=(ALL) NOPASSWD: /usr/bin/rsync --server --sender -logDtprze.iLsf --numeric-ids . /
#
# Note the NOPASSWD option in the sudo configuration. For remote
# authentication use a password-less SSH key only allowed read permissions by
# the backup server's root user.
rsync -z -e "ssh" \
	--rsync-path="$RSYNC" \
	--archive \
	--exclude-from=$EXCLUDES \
	--numeric-ids \
	--link-dest=../$YESTERDAY $SERVERNAME:/ $DESTINATION

# Backup all databases. I backup all databases into a single file. It might be
# preferable to back up each database to a separate file. If you do that, I
# suggest adding a configuration file that is looped over with a bash for() 
# loop.
ssh $SERVERNAME "mysqldump \
	--user=root \
	--password="my-super-secure-password" \
	--all-databases \
	--lock-tables \
	| bzip2" > /$BACKDIR/$SERVERNAME/db/$TODAY.sql.bz2
