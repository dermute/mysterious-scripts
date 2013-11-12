#!/bin/bash

# This is a simple backup script that uses rsync to backup files and does
# complete mysql table dumps. Note that this script DOES NOT EXPIRE OLD BACKUPS.
# Place it in /etc/cron.daily to execute it automatically. For hourly backups,
# it will need to be placed in /etc/cron.hourly, and the $TODAY / $YESTERDAY
# variables will need to be changed.

# If you want an mysql-Backup, create a file mysql.server.tld containing your mysql-root-pw

#####
# set the following Variables
#####

# Target directory for your backup
BACKDIR=/mnt/backup

# set the retention time
RETENTION=8
#RETENTIONFORMAT="day"
RETENTIONFORMAT="week"

# This is a list of files to ignore from backups.
EXCLUDES="excludes"

#####
# do not change the following
####

TODAY=`date +"%Y%m%d"`

# Set the path to rsync on the remote server so it runs with sudo.
RSYNC="/usr/bin/sudo /usr/bin/rsync"

# Servername
if [ -z "$1" ]; then
	echo "usage: ./backup.sh {servername}"
	exit 1
else
	SERVERNAME="$1"
fi

# I use a separate volume for backups. Remember that you will not be generating
# backups that are particularly large (other than the initial backup), but that
# you will be creating thousands of hardlinks on disk that will consume inodes.
DESTINATION="/$BACKDIR/$SERVERNAME/$TODAY/"

for i in {1..28}; do
	LINKDATE=`date -d "$i day ago" +"%Y%m%d"`
	if [ -d /$BACKDIR/$SERVERNAME/$LINKDATE ]; then
		break;
	fi
done

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
	--link-dest=../$LINKDATE $SERVERNAME:/ $DESTINATION

find /$BACKDIR/$SERVERNAME/ -mindepth 1 -maxdepth 1 -type d ! -name db -mtime +$RETENTION -exec rm -rf {} \;

# Backup all databases. I backup all databases into a single file. It might be
# preferable to back up each database to a separate file. If you do that, I
# suggest adding a configuration file that is looped over with a bash for() 
# loop.
if [ -f mysql.$SERVERNAME ]; then
	# Keep database backups in a separate directory.
	if [ ! -d /$BACKDIR/$SERVERNAME/db ]; then
		mkdir -p /$BACKDIR/$SERVERNAME/db
	fi

	ssh $SERVERNAME "mysqldump \
		--user=root \
		--password="`cat mysql.$SERVERNAME`" \
		--all-databases \
		--lock-tables \
		| bzip2" > /$BACKDIR/$SERVERNAME/db/$TODAY.sql.bz2
fi
