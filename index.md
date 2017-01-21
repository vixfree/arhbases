## Automated backup databases via Samba service

The script does the archive every day, every week and removes the daily, monthly - removes the daily and weekly. It is possible to forcibly cause both weekly and monthly backups. All parameters are set with the comments at the beginning of the script. In the script connects to a network drive, Windows / Linux service through samba copy these directories into a temporary directory, and then compresses them with these files names (linked to the names database directory) with the addition of the current backup date.
The script has the "entrance" - it is you connect the network drive, you must also go to some special catalog and then you can copy the database directory. This happens for example if the database location as a different resource and on ways to "input".

### Support or Contact
stvixfree@gmail.com
