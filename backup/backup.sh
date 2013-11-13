#!/bin/bash

# This is a simple backup script that uses rsync to backup files and does
# complete mysql table dumps.
# Place it in /etc/cron.daily or /etc/cron.weekly to execute it automatically.
# If you want an mysql-Backup, create a file mysql.server.tld containing your mysql-root-pw

#####
# change the following Variables
#####

# Target directory for your backup
BACKDIR=/mnt/backup

# Your Backup-User (with shared ssh-public-key)
BACKUSR=mute

# set the retention time in day(s) or week(s)
RETENTION=8
#RETENTIONFORMAT="day"
RETENTIONFORMAT="week"

# set the number of backups you want to keep
KEEP=2

# This is a list of files to ignore from backups.
EXCLUDES="excludes"

# Set the path to rsync on the remote server so it runs with sudo.
SUDO="/usr/bin/sudo"
RSYNC="$SUDO /usr/bin/rsync"

#####
# do not change the following
####

# Servername
if [ -z "$1" ]; then
	echo "usage: ./backup.sh {servername}"
	exit 1
else
	SERVERNAME="$1"
fi

TODAY=`date +"%Y%m%d"`

DESTINATION="/$BACKDIR/$SERVERNAME/$TODAY/"

if [ $RETENTIONFORMAT -eq "day" ]; then
	RETENTIONDAYS=$RETENTION
else
	RETENTIONDAYS=$((RETENTION*7))
fi

for i in {1..$RETENTIONDAYS}; do
	LINKDATE=`date -d "$i day ago" +"%Y%m%d"`
	if [ -d /$BACKDIR/$SERVERNAME/$LINKDATE ]; then
		break;
	fi
done

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
$SUDO -i $BACKUSR rsync -z -e "ssh" \
	--rsync-path="$RSYNC" \
	--archive \
	--exclude-from=$EXCLUDES \
	--numeric-ids \
	--link-dest=../$LINKDATE $SERVERNAME:/ $DESTINATION

if [ `$SUDO -i $BACKUSR find /$BACKDIR/$SERVERNAME/ -mindepth 1 -maxdepth 1 -type d ! -name db | wc -l` -gt $KEEP ]; then
	$SUDO -i $BACKUSR find /$BACKDIR/$SERVERNAME/ -mindepth 1 -maxdepth 1 -type d ! -name db -mtime +$RETENTIONDAYS -exec rm -rf {} \;
fi

# Backup all databases. I backup all databases into a single file.
if [ -f mysql.$SERVERNAME ]; then
	# Keep database backups in a separate directory.
	if [ ! -d /$BACKDIR/$SERVERNAME/db ]; then
		mkdir -p /$BACKDIR/$SERVERNAME/db
	fi

	$SUDO -i $BACKUSR ssh $SERVERNAME "mysqldump \
		--user=root \
		--password="`cat mysql.$SERVERNAME`" \
		--all-databases \
		--lock-tables \
		| bzip2" > /$BACKDIR/$SERVERNAME/db/$TODAY.sql.bz2
fi
