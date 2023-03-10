#!/bin/sh

COMMON=${COMMON:-./common.sh}

. $COMMON

UPTIME="`uptime -s`"
UPHOUR=`echo "$UPTIME" | sed 's/.* \(..\):.*/\1/'`
INF "Uphour: $UPHOUR"
if [ "$UPHOUR" -ge "2" -a "$UPHOUR" -lt "5" ];then
	WRN "Shutdown in 5 seconds!!! Press Ctrl+c to cancel"
	sleep 5
	shutdown -h now
else
	INF "Exit without shutdown"
fi
return 0

