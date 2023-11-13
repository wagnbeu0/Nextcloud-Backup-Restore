# Nextcloud-Backup-Restore

Bash scripts for backup/restore of [Nextcloud](https://nextcloud.com/).

It is based on a Nextcloud installation using nginx and PostgreSQL/MariaDB (see the (German) tutorial [Nextcloud auf Ubuntu Server 22.04 LTS mit nginx, PostgreSQL/MariaDB, PHP, Let’s Encrypt, Redis und Fail2ban](https://decatec.de/home-server/nextcloud-auf-ubuntu-server-22-04-lts-mit-nginx-postgresql-mariadb-php-lets-encrypt-redis-und-fail2ban/)).\
The scripts can also be used when Apache is used as webserver.
This fork is based on the work of https://codeberg.org/DecaTec/Nextcloud-Backup-Restore and will be maintained on https://github.com/wagnbeu0/Nextcloud-Backup-Restore

## General information

For a complete backup of any Nextcloud instance, you'll have to backup these items:
- The Nextcloud **file directory** (usually */var/www/nextcloud*)
- The **data directory** of Nextcloud (it's recommended that this is *not* located in the web root, so e.g. */var/nextcloud_data*)
- The Nextcloud **database**
- Maybe a local external storage mounted into Nextcloud

With these scripts, all these elements can be included in a backup.

## Requirements

- *pigz* (https://zlib.net/pigz/) when using backup compression. If not installed already, it can be installed with `apt install pigz` (Debian/Ubuntu). If not available, you can use another compression algorithm (e.g. gzip)

## Important notes about using the scripts

- After cloning or downloading the scripts, these need to be set up by running the script `setup.sh` (see below).
- If you do not want to use the automated setup, you can also use the file `NextcloudBackupRestore.conf.sample` as a starting point. Just make sure to rename the file when you are done (`cp NextcloudBackupRestore.conf.sample NextcloudBackupRestore.conf`)
- The configuration file `NextcloudBackupRestore.conf` has to be located in the same directory as the scripts for backup/restore.
- The scripts assume that Nextcloud's data directory is *not* a subdirectory of the Nextcloud installation (file directory). The general recommendation is that the data directory should not be located somewhere in the web folder of your webserver (usually */var/www/*), but in a different folder (e.g. */var/nextcloud_data*). For more information, see [here](https://docs.nextcloud.com/server/latest/admin_manual/installation/installation_wizard.html#data-directory-location-label).
- However, if your data directory *is* located under the Nextcloud file directory, you'll have to change the script configuration (file `NextcloudBackupRestore.conf` after running `setup.sh`) so that the data directory is not part of the backup/restore (otherwise, it would be copied twice).
- The scripts only backup the Nextcloud data directory and can backup a local external storage mounted into Nextcloud. If you have any other external storage mounted in Nextcloud (e.g. FTP), these files have to be handled separately.
- The scripts support nginx and Apache as webserver.
- The scripts support MariaDB/MySQL and PostgreSQL as database.
- You should have enabled 4 byte support (see [Nextcloud Administration Manual](https://docs.nextcloud.com/server/latest/admin_manual/configuration_database/mysql_4byte_support.html)) on your Nextcloud database. Otherwise, when you have *not* enabled 4 byte support, you have to edit the restore script, so that the database is not created with 4 byte support enabled (variable `dbNoMultibyte`).
- The scripts can exclude the Nextcloud data directory from backup and restore.\
**WARNING**: Excluding the data directory is **NOT RECOMMENDED** as it leaves the backup in an inconsistent state and may result in data loss!

## Setup

1. Clone the repository: `git clone https://github.com/wagnbeu0/Nextcloud-Backup-Restore.git)`
2. Set permissions:
    - `chown -R root Nextcloud-Backup-Restore`
    - `cd Nextcloud-Backup-Restore`
    - `chmod 700 *.sh`
3. Call the (interactive) script for automated setup (this will create a file `NextcloudBackupRestore.conf` containing the desired configuration): `./setup.sh`
4. **Important**: Check this configuration file if everything was set up correctly (see *TODO* in the configuration file comments)
5. Start using the scripts: See sections *Backup* and *Restore* below

Keep in mind that the configuration file `NextcloudBackupRestore.conf` hast to be located in the same directory as the scripts for backup/restore, otherwise the configuration will not be found.

Some optional options are not configured using `setup.sh`, but are set to default values in `NextcloudBackupRestore.conf`. These are the "dangerous" options which usually should not be changed and are marked as 'OPTIONAL' in `NextcloudBackupRestore.conf`

## Backup

In order to create a backup, simply call the script *NextcloudBackup.sh* on your Nextcloud machine.
If this script is called without parameter, the backup is saved in a directory with the current time stamp in your main backup directory: As an example, this would be */media/hdd/nextcloud_backup/20170910_132703*.
The backup script can also be called with a parameter specifying the main backup directory, e.g. *./NextcloudBackup.sh /media/hdd/nextcloud_backup*. In this case, the directory specified will be used as main backup directory. 

You can also call this script by cron. Example (at 2am every night, with log output):

`0 2 * * * /path/to/scripts/Nextcloud-Backup-Restore/NextcloudBackup.sh  > /path/to/logs/Nextcloud-Backup-$(date +\%Y\%m\%d\%H\%M\%S).log 2>&1`

## Restore

Call *NextcloudRestore.sh* in order to restore a backup.\
When this script is called without parameters, it lists the backups available for restore.\
In order to restore a backup, call this script with a parameter specifying the name (i.e. timestamp) of the backup to be restored. In this example, this would be *20170910_132703*. The full command for a restore would be *./NextcloudRestore.sh 20170910_132703*.
You can also specify the main backup directory with a second parameter, e.g. *./NextcloudRestore.sh 20170910_132703 /media/hdd/nextcloud_backup*.
