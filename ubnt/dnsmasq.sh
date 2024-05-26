#!/bin/sh
CONF="/etc/dnsmasq.conf"
CONF_LIST="$CONF /etc/dnsmasq.d/dnsmasq-dhcp-config.conf"
############################
TEST_ONLY=${TEST_ONLY:-0}
DEBUG=${DEBUG:-0}
DBG_FILE=/tmp/`basename $0`_dbg.log
rm -rf $DBG_FILE
############################
DBG()
{
	echo "$@"
	[ "$DEBUG" = "1" ] && echo "$@" >>$DBG_FILE
}
############################
USAGE(){
	echo "Usage: $1 [params]"
	echo "     -T: Test run, does not actually take effect"
	echo "     -D: debug mode"
	echo "     -h: print this"

	exit -1
}
while getopts "TD" opt; do
	case $opt in
		T)
			TEST_ONLY=1
		;;
		D)
			DEBUG=1
		;;
		*)
			USAGE $0
		;;
	esac
done
DBG "TEST:$TEST_ONLY, DEBUG: $DEBUG"
############################
[ -f ./$CONF ] && {
	CONF=.$CONF
	CONF_LIST=`echo $CONF_LIST | sed 's/^/ /;s/ \// .\//g'`
}
DBG "Config files: $CONF_LIST"

subnet2range(){
	local ip
	local stop
	local start
	local value
	for ip in $@
	do
		start=`echo $ip | sed 's/\/.*//'`
		[ "$start" = "$ip" ] && {
			echo -n "$ip "
			continue
		}
		value=`echo $ip | sed 's/.*\///'`
		value=$((32-value))
		value=$((1<<value))
		value=$((value-1))
		stop=$((start+value))
		echo -n "$start/$stop "
	done
}
digtal_in_range(){
	local data
	local value
	local stop
	local start
	local list
	value=$1
	shift
	list=$@
	for data in $list
	do
		[ "$value" = "$data" ] && return 0
		start=${data/\// }
		[ "$start" = "$data" ] && continue
		set -- $start
		start=$1;stop=$2
		[ -z "$start" -o -z "$stop" ] && continue
		[ $value -ge $start -a $value -le $stop ] && return 0
	done
	return 1
}
ip_in_range(){
	local dig
	dig=$1
	shift
	dig=`echo $dig | sed 's/.*\.//'`
	digtal_in_range $dig $@
}

read_conf(){
	local value
	for file in $CONF_LIST
	do
		value=`cat $file | sed "/\b$1/!d;s/.*\b$1 *//;q"`
		[ -n "$value" ] && {
			echo $value
			return 0
		}
	done
	return 1
}

filter_directDNS()
{
	# filter for direct-DNS query
	/sbin/iptables -t filter -D VYATTA_FW_OUT_HOOK -p udp --dport 53 -j dns_filter 2>/dev/null
	DBG "/sbin/iptables -t filter -A VYATTA_FW_OUT_HOOK -p udp --dport 53 -j dns_filter"
	/sbin/iptables -t filter -A VYATTA_FW_OUT_HOOK -p udp --dport 53 -j dns_filter
}

dnsmasq_set_directDNS_line(){
	local ip
	ip=`echo "$1" | sed '/dhcp-host=.*,set:LAN,/!d;/set:LAN,set:directdns/d;s/.*,\([0-9\.]\{7,15\}\).*/\1/'`
	[ -z "$ip" ] && echo "$1" && return
	ip_in_range $ip $directDNS_range || {
		echo "$1"
		return
	}
	echo "$1" | sed 's/set:LAN/set:LAN,set:directdns/'
}
dnsmasq_set_directDNS(){
	local file
	local host
	file=/tmp/`basename $1`.tmp
	rm -rf $file
	while IFS= read -r line;do
		line=`dnsmasq_set_directDNS_line "$line"`

		echo "$line" >>$file
	done <$1
	if [ "$TEST_ONLY" = "1" ]
	then
		cat $file
	else
		# check if changed
		cmp $file $1 >/dev/null || mv $file $1
	fi
	[ "$DEBUG" != "1" ] && rm -rf $file
}
dnsmasq_disable_dns(){
	local dnsport
	dnsport=`read_conf "port="`
	[ -z "$dnsport" ] && echo "port=0" >>$CONF && return
	sed -i 's/\bport=[[:digit:]]*/port=0/' $CONF_LIST
}

# reconfig dnsmasq
subnet=`read_conf "subnet " | sed 's/\.[0-9]\+\/.*//'`
DBG "Subnets: $subnet"
directdns_list=`/sbin/ipset -L directDNS 2>/dev/null | sed '1,8d' | sed "s/$subnet\.//g"`
DBG "Direct DNS CIDR list: $directdns_list"
[ -z "$directdns_list" ] && {
	DBG "Can not find device/IP list from ipset(directDNS)"
	exit 1
}
directDNS_range=`subnet2range $directdns_list`
DBG "Direct DNS range: $directDNS_range"
for file in $CONF_LIST;do
	DBG "Processing file $file"
	dnsmasq_set_directDNS $file
done
DBG "Disable DNS of dnsmasq"
dnsmasq_disable_dns
DBG "Setup iptables for direct DNS"
filter_directDNS
# restart dnsmasq
DBG "Restart dnsmasq"
[ "$TEST_ONLY" != "1" ] && systemctl restart dnsmasq
# start smartDNS
DBG "Restart smartdns"
[ "$TEST_ONLY" != "1" ] && systemctl restart smartdns
exit 0
