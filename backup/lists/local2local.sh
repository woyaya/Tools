# username@server   remote_dir    local_dir     relative     rsync_params
# username@server: user name and remote server address
#	EMPTY: rsync from local to local
#	others: rsync from server to local
# remote_dir: source dir at remote server(or local machine if "username@server" is empty
#	if "remote_dir" end with '/': sync with context of remote_dir only
#	if "remote_dir" end without '/': sync with remote path and context of the remote_dir
# local_dir: dist dir of local machine
# relative: Create relative path or not
#	y: Create relative path
#	n: Do not create relative path
# rsync_params: additional parameters of rsync

# username@server   remote_dir    local_dir     relative     rsync_params
,/etc/apache2,/home/share/Backup/GeminiM,y,
,/etc/docker,/home/share/Backup/GeminiM,y,
,/etc/mosquitto,/home/share/Backup/GeminiM,y,
,/etc/network,/home/share/Backup/GeminiM,y,
,/etc/samba,/home/share/Backup/GeminiM,y,
,/home/user/.bash_aliases,/home/share/Backup/GeminiM,y,
,/home/user/.gitconfig,/home/share/Backup/GeminiM,y,
,/home/user/.tmux.conf,/home/share/Backup/GeminiM,y,
,/home/user/.ssh/config,/home/share/Backup/GeminiM,y,
,/home/user/.vim,/home/share/Backup/GeminiM,y,
,/home/user/.vimrc,/home/share/Backup/GeminiM,y,
,/home/www/dokuwiki/conf,/home/share/Backup/GeminiM,y,
,/home/www/dokuwiki/data/pages,/home/share/Backup/GeminiM,y,
,/home/www/dokuwiki/data/attic,/home/share/Backup/GeminiM,y,--exclude _dummy
,/home/www/dokuwiki/data/media*,/home/share/Backup/GeminiM,y,--exclude _dummy
,/home/www/dokuwiki/data/meta,/home/share/Backup/GeminiM,y,--exclude _dummy
,/home/smarthome/esphome/*.yaml,/home/share/Backup/GeminiM,y,
,/home/smarthome/esphome/SRC,/home/share/Backup/GeminiM,y,
,/home/smarthome/hassio,/home/share/Backup/GeminiM,y,--exclude *.db* --exclude *.log* --exclude .git --exclude *backup --exclude test --exclude log --exclude tmp --exclude .storage/auth --exclude .storage/core.restore_state
,/home/share/Backup/GeminiM,/home/Backup,n,
