#!/bin/sh

COMMON=${COMMON:-./common.sh}

. $COMMON

UPTIME="`uptime -s`"
UPTIME=`date -d "$UPTIME" +%H%M`
INF "Uptime: $UPTIME"
if [ "$UPTIME" -ge "0130" -a "$UPTIME" -lt "0500" ];then
	WRN "Shutdown in 5 seconds!!! Press Ctrl+c to cancel"
	sleep 5
	shutdown -h now
else
	INF "Exit without shutdown"
fi
return 0

