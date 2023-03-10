#!/bin/bash
#Functions
############################
USAGE(){
	echo "Usage: $1 [params]"
	echo "     -b BASE: base dir, where to find configs and functions. default: ./"
	echo "     -l list_file: read list from this file. default: backup.lst"
	echo "     -P script: script to be executed after config generated"
	echo "     -N: do NOT create relative path at dist dir"
	echo "     -v: more verbose output"
	echo "     -L: log to logger"
	echo "     -D: debug mode"
	echo "     -h: print this"

	exit -1
}
cleanup() {
	LOG "Cleanup $WORK_DIR: $DELETE"
	[ "$DELETE" != "0" ] && {
		[ -d $WORK_DIR ] && rm  -rf $WORK_DIR
	}
}
#1: ERR; 2:ERR+WRN; 3:ERR+WRN+INF
LOG_LEVEL=${LOG_LEVEL:-2}
LOG2LOGGER=${LOG2LOGGER:-0}
DEBUG=${DEBUG:-0}
SCRIPT=()
RELATIVE=1
############################
while getopts ":b:l:P:NvLD" opt; do
	case $opt in
		b)
			BASE=$OPTARG
		;;
		l)
			LIST=$OPTARG
		;;
		P)
			SCRIPT+=("$OPTARG")
		;;
		N)
			RELATIVE=0
		;;
		v)
			LOG_LEVEL=$((LOG_LEVEL+1))
		;;
		L)
			LOG2LOGGER=1
		;;
		D)
			DEBUG=1
			DELETE=0
			LOG_LEVEL=999
		;;
		*)
			USAGE $0
		;;
	esac
done

EXEC=`basename $0`
DIR=`dirname $0`
export EXEC
export DEBUG
export LOG_LEVEL

#Dir && files
BASE=${BASE:-$DIR}
FUNC_DIR=${BASE}/functions
SCRIPT_DIR=${BASE}/scripts
export BASE BASE_DIR FUNC_DIR 

COMMON=$BASE/common.sh
[ ! -f $COMMON ] && COMMON=$FUNC_DIR/common.sh
[ ! -f $COMMON ] && {
	echo "Invalid setting! file \"$COMMON\" not exist"
	exit 1
}
export COMMON
. $COMMON

LIST_DIR=${BASE}/Backup
LIST=${LIST:-backup.lst}
[ ! -f $LIST ] && LIST=$LIST_DIR/$LIST
[ ! -f $LIST ] && ERR "Can not found list file: $LIST"

check_dirs $SCRIPT_DIR $LIST_DIR || ERR "Incompleted dirs"
check_execs rsync logger sed awk wc || ERR "Incomplete executes"

#WORK_DIR=/tmp/$EXEC
#export WORK_DIR
#mkdir -p $WORK_DIR
#trap cleanup EXIT

FAIL=""
SUCC=""
[ "$LOG_LEVEL" -ge "4" ] && VERBOSE="-v" || VERBOSE="-q"
[ `whoami` = "root" ] && PRESERVE="-X" || PRESERVE=""
INF "Read list from $LIST"
while read LINE; do
	DBG "Process line: $LINE"
	[ -z "$LINE" ] && continue
	line=`echo "$LINE" | sed 's/^ *//;/^#/d'`
	DBG "Ignor annotation: $line"
	[ -z "$line" ] && continue
	server=`echo "$line" | awk -F, '{print $1}' | sed 's/^ *//'`
	remote_dir=`echo "$line" | awk -F, '{print $2}' | sed 's/^ *//'`
	local_dir=`echo "$line" | awk -F, '{print $3}' | sed 's/^ *//'`
	relative=`echo "$line" | awk -F, '{print $4}'`
	params=`echo "$line" | awk -F, '{print $5}' | sed 's/^ *//'`
	check=`echo "$line" | awk -F, '{print $6}'`
	[ "$relative" != "n" ] && RELATIVE="-R" || RELATIVE=""
	LOG "Server: $server, remote dir: $remote_dir, local dir: $local_dir, param: $param"
	[ -n "$check" ] && {
		WRN "Invalid line(Too many comma): $LINE"
		FAIL="$FAIL*<$LINE>: Too many comma"
		continue
	}
	check_variables remote_dir local_dir || {
		WRN "Invalid line(Too less comma): $LINE"
		FAIL="$FAIL*<$LINE>: Too less comma"
		continue
	}
	#name=`ssh -n $server 'uname -n'`
	#DBG "Remote host name: $name"
	if [ -n "$server" ];then
		remote="$server:$remote_dir"
		params="-azzP $RELATIVE $PRESERVE --noatime $params $VERBOSE -e ssh"
	else
		remote="$remote_dir"
		[ ! -d "$remote" ] && {
			#Check if "remote" is file
			is_dir=`echo "$remote" | sed '/\/$/!d'`
			[ -n "$is_dir" ] && {
				WRN "Invalid dir: $remote"
				FAIL="$FAIL*<$LINE>: Invalid dir: $remote"
				continue
			}
			dir=`dirname $remote | uniq`
			[ ! -d "$dir" ] && {
				WRN "Invalid file: $remote"
				FAIL="$FAIL*<$LINE>: Invalid file: $remote"
				continue
			}
		}
		params="-aHA $RELATIVE $PRESERVE --noatime $params $VERBOSE"
	fi
	LOG "Backup from $remote to $local_dir with params($params)"
	# Backup to local device
	mkdir -p $local_dir
	DBG "rsync $params $remote $local_dir"
	rsync $params $remote $local_dir
	if [ $? = 0 ];then
		SUCC="$SUCC*<$LINE>"
		INF "Backup $remote to $local_dir success"
	else
		WRN "Backup $remote to $local_dir fail"
		FAIL="$FAIL*<$LINE>: rsync fail"
	fi
done <$LIST

DBG "Process end: $LIST"
[ -n "$SUCC" ] && INF "Backup succ list: `echo "$SUCC" | sed 's/\*</\n\t</g'`"
[ -n "$FAIL" ] && WRN "Backup fail list: `echo "$FAIL" | sed 's/\*</\n\t</g'`"

[ "${#SCRIPT[@]}" -ge 1 ] && {
	for script in ${SCRIPT[@]};do
		INF "Run post script: $script"
		cmd=""
		[ -x $SCRIPT_DIR/$script ] && cmd=$SCRIPT_DIR/$script
		[ -x $BASE/$script ] && cmd=$BASE/$script
		[ -x $script ] && cmd=$script
		[ -z "$cmd" ] && ERR "Can not find script: $script"
		$cmd
	done
}

INF "Backup done: $LIST"
