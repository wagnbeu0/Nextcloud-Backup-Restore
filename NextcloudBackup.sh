#!/bin/bash

#
# Bash script for creating backups of Nextcloud. This Script is based on the work of https://codeberg.org/DecaTec/Nextcloud-Backup-Restore
#
# Version 3.3.1
#
# Requirements:
#	- pigz (https://zlib.net/pigz/) for using backup compression. If not available, you can use another compression algorithm (e.g. gzip)
#	- rsync for using noncopmpressed backups.
#
# Supported database systems:
# 	- MySQL/MariaDB
# 	- PostgreSQL
#
# Usage:
# 	- With backup directory specified in the script:  ./NextcloudBackup.sh
# 	- With backup directory specified by parameter: ./NextcloudBackup.sh <backupDirectory> (e.g. ./NextcloudBackup.sh /media/hdd/nextcloud_backup)
#
# The script is based on an installation of Nextcloud using nginx and MariaDB, see https://decatec.de/home-server/nextcloud-auf-ubuntu-server-22-04-lts-mit-nginx-postgresql-mariadb-php-lets-encrypt-redis-und-fail2ban/
#


# Make sure the script exits when any command fails
set -Eeuo pipefail

# Variables
working_dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
configFile="${working_dir}/NextcloudBackupRestore.conf"   # Holds the configuration for NextcloudBackup.sh and NextcloudRestore.sh
_backupMainDir=${1:-}

# Function for error messages
errorecho() { cat <<< "$@" 1>&2; }

#
# Check for root
#
if [ "$(id -u)" != "0" ]
then
	errorecho "ERROR: This script has to be run as root!"
	exit 1
fi

#
# Check if config file exists
#
if [ ! -f "${configFile}" ]
then
	errorecho "ERROR: Configuration file $configFile cannot be found!"
	errorecho "Please make sure that a configuratrion file '$configFile' is present in the main directory of the scripts."
	errorecho "This file can be created automatically using the setup.sh script."
	exit 1
fi

source "$configFile" || exit 1  # Read configuration variables

if [ -n "$_backupMainDir" ]; then
	backupMainDir=$(echo $_backupMainDir | sed 's:/*$::')
fi

currentDate=$(date +"%Y%m%d_%H%M%S")

# The actual directory of the current backup - this is a subdirectory of the main directory above with a timestamp
backupDir="${backupMainDir}/${currentDate}"

function DisableMaintenanceMode() {
	echo "$(date +"%H:%M:%S"): Switching off maintenance mode..."
	sudo -u "${webserverUser}" php ${nextcloudFileDir}/occ maintenance:mode --off
	echo "Done"
	echo
}

function occ_get() {
	sudo -u "${webserverUser}" php ${nextcloudFileDir}/occ config:system:get "$1"
}

if [ "${databaseSystem,,}" = "mysql" ] || [ "${databaseSystem,,}" = "mariadb" ]; then
  fourByteSupport=$(occ_get mysql.utf8mb4) || (errorecho "ERROR: OCC config:system:get call failed!" && exit 1)
fi

# Capture CTRL+C
trap CtrlC INT

function CtrlC() {
	read -p "Backup cancelled. Keep maintenance mode? [y/n] " -n 1 -r
	echo

	if ! [[ $REPLY =~ ^[Yy]$ ]]
	then
		DisableMaintenanceMode
	else
    echo "Maintenance mode still enabled."
	fi

	echo "Starting web server..."
	systemctl start "${webserverServiceName}"
	echo "Done"
	echo

	exit 1
}

#
# Print information
#
echo "Backup directory: ${backupMainDir}"

#
# Check if backup dir already exists
#
if [ ! -d "${backupDir}" ]
then
	mkdir -p "${backupDir}"
else
	errorecho "ERROR: The backup directory ${backupDir} already exists!"
	exit 1
fi

#
# Set maintenance mode
#
echo "$(date +"%H:%M:%S"): Set maintenance mode for Nextcloud..."
sudo -u "${webserverUser}" php ${nextcloudFileDir}/occ maintenance:mode --on
echo "Done"
echo

#
# Stop web server
#
echo "$(date +"%H:%M:%S"): Stopping web server..."
systemctl stop "${webserverServiceName}"
echo "Done"
echo

#
# Backup file directory
#
echo "$(date +"%H:%M:%S"): Creating backup of Nextcloud file directory..."

if [ "$useCompression" = true ] ; then
	if [ "$includeNextcloudDataDir" = false ]; then
		echo "$(date +"%H:%M:%S"): Creating compressed tar backup of Nextcloud file directory without data subfolder..."
		`$compressionCommand "${backupDir}/${fileNameBackupFileDir}" --exclude="./data/*" -C "${nextcloudFileDir}" .`
	else
		echo "$(date +"%H:%M:%S"): Creating compressed tar backup of Nextcloud file directory with data subfolder..."
		`$compressionCommand "${backupDir}/${fileNameBackupFileDir}" -C "${nextcloudFileDir}" .`
	fi
else
	if [ "$includeNextcloudDataDir" = false ]; then
		if [ -d "${backupMainDir}/latest" ]; then
			echo "$(date +"%H:%M:%S"): Create incremental backup using rsync without data subfolder..."
			rsync -aug "${nextcloudFileDir}/" --link-dest "${backupMainDir}/latest/" "${backupDir}/${folderNameBackupFileDir}/" --exclude "data/*" 
		else
			echo "$(date +"%H:%M:%S"): Create full backup using rsync without data subfolder..."
			rsync -aug "${nextcloudFileDir}/" "${backupDir}/${folderNameBackupFileDir}/" --exclude "data/*" 
		fi
	else
		if [ -d "${backupMainDir}/latest" ]; then
			echo "$(date +"%H:%M:%S"): Create incremental backup using rsync with data subfolder..."
			rsync -aug "${nextcloudFileDir}/" --link-dest "${backupMainDir}/latest/" "${backupDir}/${folderNameBackupFileDir}/" 
		else
			echo "$(date +"%H:%M:%S"): Create full backup using rsync with data subfolder..."
			rsync -aug "${nextcloudFileDir}/" "${backupDir}/${folderNameBackupFileDir}/" 
		fi
	fi
fi

echo "Done"
echo

#
# Backup data directory
#
if [ "$includeNextcloudDataDir" = false ]; then
	echo "$(date +"%H:%M:%S"): Ignoring backup of Nextcloud data directory!"
elif [[ "${nextcloudDataDir}" = "${nextcloudFileDir}"* ]] && [ "$includeNextcloudDataDir" = true ]; then
	echo "$(date +"%H:%M:%S"): Skipping backup of Nextcloud data directory (already included in file directory backup)!"
else
	echo "$(date +"%H:%M:%S"): Creating backup of Nextcloud data directory..."

	if [ "$includeUpdaterBackups" = false ] ; then
		echo "Ignoring Nextcloud updater backup directory"

		if [ "$useCompression" = true ] ; then
			echo "$(date +"%H:%M:%S"): Creating compressed tar backup"
			`$compressionCommand "${backupDir}/${fileNameBackupDataDir}"  --exclude="updater-*/backups/*" -C "${nextcloudDataDir}" .`
		else
			if [ -d "${backupMainDir}/latest" ]; then
			echo "$(date +"%H:%M:%S"): Creating incremental rsync backup"
			rsync -aug "${nextcloudDataDir}/" --link-dest "${backupMainDir}/latest/" "${backupDir}/${folderNameBackupDataDir}/" --exclude "updater-*/backups/*"			
			else
c
			rsync -aug "${nextcloudDataDir}/" "${backupDir}/${folderNameBackupDataDir}/" --exclude "updater-*/backups/*"
			fi	
		fi
	else
		if [ "$useCompression" = true ] ; then
			echo "$(date +"%H:%M:%S"): Creating compressed tar backup"
			`$compressionCommand "${backupDir}/${fileNameBackupDataDir}"  -C "${nextcloudDataDir}" .`
		else
			if [ -d "${backupMainDir}/latest" ]; then
			echo "$(date +"%H:%M:%S"): Creating incremental rsync backup"
			rsync -aug "${nextcloudDataDir}/" --link-dest "${backupMainDir}/latest/" "${backupDir}/${folderNameBackupDataDir}/"			
			else
			echo "$(date +"%H:%M:%S"): Creating incremental rsync backup"
			rsync -aug "${nextcloudDataDir}/" "${backupDir}/${folderNameBackupDataDir}/"
			fi
		fi
	fi
fi

echo "Done"
echo

#
# Backup local external storage.
#
if [ ! -z "${nextcloudLocalExternalDataDir+x}" ] ; then
	echo "$(date +"%H:%M:%S"): Creating backup of Nextcloud local external storage directory..."

	if [ "$useCompression" = true ] ; then
		`$compressionCommand "${backupDir}/${fileNameBackupExternalDataDir}"  -C "${nextcloudLocalExternalDataDir}" .`
	else
		tar -cpf "${backupDir}/${fileNameBackupExternalDataDir}"  -C "${nextcloudLocalExternalDataDir}" .
	fi

	echo "Done"
	echo
fi

#
# Backup DB
#
if [ "${databaseSystem,,}" = "mysql" ] || [ "${databaseSystem,,}" = "mariadb" ]; then
  	echo "$(date +"%H:%M:%S"): Backup Nextcloud database (MySQL/MariaDB)..."

	if ! [ -x "$(command -v mysqldump)" ]; then
		errorecho "ERROR: MySQL/MariaDB not installed (command mysqldump not found)."
		errorecho "ERROR: No backup of database possible!"
	else
		if [ $fourByteSupport = "true" ]; then
			mysqldump --single-transaction --default-character-set=utf8mb4 -h localhost -u "${dbUser}" -p"${dbPassword}" "${nextcloudDatabase}" > "${backupDir}/${fileNameBackupDb}"
		else
			mysqldump --single-transaction -h localhost -u "${dbUser}" -p"${dbPassword}" "${nextcloudDatabase}" > "${backupDir}/${fileNameBackupDb}"
		fi
	fi

	echo "Done"
	echo
elif [ "${databaseSystem,,}" = "postgresql" ] || [ "${databaseSystem,,}" = "pgsql" ]; then
	echo "$(date +"%H:%M:%S"): Backup Nextcloud database (PostgreSQL)..."

	if ! [ -x "$(command -v pg_dump)" ]; then
		errorecho "ERROR: PostgreSQL not installed (command pg_dump not found)."
		errorecho "ERROR: No backup of database possible!"
	else
		PGPASSWORD="${dbPassword}" pg_dump "${nextcloudDatabase}" -h localhost -U "${dbUser}" -f "${backupDir}/${fileNameBackupDb}"
	fi

	echo "Done"
	echo
fi

#
# Start web server
#
echo "$(date +"%H:%M:%S"): Starting web server..."
systemctl start "${webserverServiceName}"
echo "Done"
echo

#
# Disable maintenance mode
#
DisableMaintenanceMode

#
# Delete old backups
#
if [ ${maxNrOfBackups} != 0 ]
then
	nrOfBackups=$(ls -l ${backupMainDir} | grep -c ^d)

	if [ ${nrOfBackups} -gt ${maxNrOfBackups} ]
	then
		echo "$(date +"%H:%M:%S"): Removing old backups..."
		ls -t ${backupMainDir} | tail -$(( nrOfBackups - maxNrOfBackups )) | while read -r dirToRemove; do
			echo "${dirToRemove}"
			rm -r "${backupMainDir}/${dirToRemove:?}"
			echo "Done"
			echo
		done
	fi
fi

echo
echo "DONE!"
echo "$(date +"%H:%M:%S"): Backup created: ${backupDir}"

# Set this backup as latest
rm -rf "${backupMainDir}/latest"
ln -s "${backupDir}" "${backupMainDir}/latest"

set +Eeuo pipefail
