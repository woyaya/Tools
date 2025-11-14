#!/bin/bash
HOST=`hostname -s`
#Functions
############################
USAGE(){
	echo "Usage: $1 [params]"
	echo "     -u: update self before any action"
	echo "     -b BASE: base dir, where to find configs and functions. default: ./"
	echo "     -l list_file: read list from this file. default: $HOST.lst"
	echo "     -P script: script to be executed after config generated"
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
check_src(){
	local param=$1
	local dir
	local list
	[ -d "$param" -o -f "$param" ] && return 0
	# not dir, check if file
	dir=`echo "$param" | sed '/\/$/!d'`
	[ -n "$dir" ] && return 1
	dir=`dirname "$param" | uniq`
	[ ! -d "$dir" ] && return 1
	# maybe "dir/file*"
	list=`ls $param 2>/dev/null`
	[ -z "$list" ] && return 1
	return 0
}
rsync_version(){
	[ -z "$1" ] && {
		rsync --version | sed '/version/!d;s/.*version \([0-9]\)\.\([0-9]\).* protocol.*/\1\2/'
		return
	}
	ssh -n $1 'rsync --version 2>/dev/null' | sed '/version/!d;s/.*version \([0-9]\)\.\([0-9]\).* protocol.*/\1\2/'
}
atime(){
	local rversion
	[ -n "$1" ] && rversion=`rsync_version "$1"` || rversion="$LVERSION"
	[ -z "$rversion" ] && return 1
	[ "$rversion" -ge 32 -a "$LVERSION" -ge 32 ] && {
		echo "--open-noatime"
		return 0
	}
	[ "$rversion" -lt 32 -a "$LVERSION" -lt 32 ] && {
		echo "--noatime"
		return 0
	}
	#unmatch version, 'atime' is not supported
	return 0;
}

dist_dir_extend(){
	local exist
	exist=`echo $1 | sed '/\${.*}/!d'`
	if [ -z "$exist" ]
	then
		echo -n "$1"
	else
		eval echo -n "$1"
	fi
}

#1: ERR; 2:ERR+WRN; 3:ERR+WRN+INF
LOG_LEVEL=${LOG_LEVEL:-2}
LOG2LOGGER=${LOG2LOGGER:-0}
UPDATE=${UPDATE:-0}
DEBUG=${DEBUG:-0}
SCRIPT=()
export HOST
export WEEK=$(date +%A)
export MONTH=$(date +%m)
export YEAR=$(date +%Y)
export DATE=$(date +%Y%m%d)
############################
while getopts ":b:l:P:uvLD" opt; do
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
		u)
			UPDATE=1
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

[ "$UPDATE" = "1" ] && {
	_PWD=$(pwd)
	INF "Update $BASE before actions"
	cd $BASE && git pull 2>/dev/null
	cd $_PWD
}

LIST_DIR=${BASE}/lists
if [ -z "$LIST" ]
then
	WRN "No list file was specified; the default value is set to $HOST.lst."
	list=$HOST.lst
else
	list="$LIST"
fi
LIST=$list
[ ! -f $LIST ] && LIST=$LIST_DIR/$list
[ ! -f $LIST ] && LIST=$BASE/$list
[ ! -f $LIST ] && ERR "Can not found list file: $list"

check_dirs $SCRIPT_DIR $LIST_DIR || ERR "Incompleted dirs"
check_execs rsync logger sed awk wc || ERR "Incomplete executes"

#WORK_DIR=/tmp/$EXEC
#export WORK_DIR
#mkdir -p $WORK_DIR
#trap cleanup EXIT

FAIL=""
SUCC=""
LVERSION=`rsync_version`
[ "$LOG_LEVEL" -ge "5" ] && VERBOSE="-v" || VERBOSE="-q"
[ `whoami` = "root" ] && PRESERVE="-X" || PRESERVE=""
INF "Read list from $LIST"

while read LINE; do
	DBG "Process line: $LINE"
	[ -z "$LINE" ] && continue
	line=`echo "$LINE" | sed 's/^ *//;/^#/d'`
	DBG "Ignor annotation: $line"
	[ -z "$line" ] && continue
	src=`echo "$line" | awk -F, '{print $1}' | sed 's/^ *//;s/ *$//'`
	DIST=`echo "$line" | awk -F, '{print $2}' | sed 's/^ *//;s/ *$//'`
	dist=`dist_dir_extend "$DIST"`
	params=`echo "$line" | awk -F, '{print $3}' | sed 's/^ *//;s/ *$//'`
	check=`echo "$line" | awk -F, '{print $4}'`
	LOG "src: $src, dist: $dist($DIST), Param: $params"
	[ -n "$check" ] && {
		WRN "Invalid line(Too many comma): $LINE"
		FAIL="$FAIL*<$LINE>: Too many comma"
		continue
	}
	check_variables src dist || {
		WRN "Invalid line(Too less comma): $LINE"
		FAIL="$FAIL*<$LINE>: Too less comma"
		continue
	}
	# parse variables
	src_server=`echo "$src" | sed '/:/!d;/\/.*:/d;s/:.*//'`
	dist_server=`echo "$dist" | sed '/:/!d;/\/.*:/d;s/:.*//'`
	[ -n "$src_server" -a -n "$dist_server" ] && {
		WRN "Cannot both be remote: $src, $dist"
		FAIL="$FAIL*<$LINE>: Cannot both be remote"
		continue
	}

	#check if 'src' end with '/'
	backslash=`echo "$src" | sed '/\/$/!d'`
	[ -n "$backslash" ] && RELATIVE="" || RELATIVE="-R"
	params="$(rsync_params $RELATIVE $params)"
	if [ -n "$src_server" ];then
		src_param="-zP -e ssh"
		dist_param=""
		mkdir -p $dist
	elif [ -n "$dist_server" ];then
		src_param="-zP "
		dist_param="-e ssh"
		check_src $src || {
			WRN "invalid source: $src"
			fail="$fail*<$line>: invalid source: $src"
			continue
		}
	else
		check_src $src || {
			WRN "invalid source: $src"
			fail="$fail*<$line>: invalid source: $src"
			continue
		}
		src_param=""
		dist_param=""
		mkdir -p $dist
	fi
	LOG "Backup from $src to $dist($DIST) with params($params $src_param $dist_param)"
	# Backup to local device
	LOG "rsync $params $src_param $src $dist_param $dist"
	rsync $params $src_param $src $dist_param $dist
	if [ $? = 0 ];then
		SUCC="$SUCC*<$LINE>"
		INF "Backup $src to $dist($DIST) success"
	else
		WRN "Backup $src to $dist($DIST) fail"
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
