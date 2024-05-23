#!/bin/bash
[ -d ./etc ] && BASEDIR=. || BASEDIR=""
CONF="$BASEDIR/etc/dnsmasq.conf"
CONF_LIST="$CONF $BASEDIR/etc/dnsmasq.d/dnsmasq-dhcp-config.conf"
NAME=directDNS_filter
DIRECTDNS_LIST="128/26 11 8"

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
		value=`cat $file | sed "/$1/!d;s/.*$1 *//;q"`
		[ -n "$value" ] && {
			echo $value
			return 0
		}
	done
	return 1
}

filter_directDNS()
{
	# flush target chain or create it
	iptables -t filter -F $NAME || iptables -t filter -N $NAME || return
	# filter for DNS query
	iptables -t filter -A FORWARD -p udp --dport 53 -j $NAME
	# Enable ip ranges for direct-DNS device
	for ip in $DIRECTDNS_LIST;do
		iptables -t filter -A $NAME -s $subnet.$ip -j ACCEPT
	done
	# Disable direct DNS query for all other devices
	iptables -t filter -A $NAME -j DROP
	# Disable IPv6 direct DNS query for all devices
	ip6tables -t filter -D FORWARD -p udp --dport 53 -j DROP 2>/dev/null
	ip6tables -t filter -A FORWARD -p udp --dport 53 -j DROP
}

dnsmasq_set_directDNS(){
	local ip
	ip=`echo "$1" | sed '/dhcp-host=.*,set:LAN,/!d;s/.*,\([0-9\.]\{7,15\}\).*/\1/'`
	[ -z "$ip" ] && echo "$1" && return
	ip_in_range $ip $directDNS_range || {
		echo "$1"
		return
	}
	echo "$1" | sed 's/set:LAN/set:LAN,set:directdns/'
}
dnsmasq_remove_port(){
	echo "$1" | sed 's/\bport=[[:digit:]]*/port=0/'
}
reconfig_dnsmasq(){
	local file
	local host
	file=/tmp/`basename $1`.tmp
	rm -rf $file
	while read line;do
		line=`dnsmasq_set_directDNS "$line"`
		line=`dnsmasq_remove_port "$line"`

		echo "$line" >>$file
	done <$1
	cat $file
	rm $file
}

# stop dnsmasq
#systemctl stop dnsmasq
# reconfig dnsmasq
subnet=`read_conf "subnet " | sed 's/\.[0-9]*\/.*//'`
directDNS_range=`subnet2range $DIRECTDNS_LIST`
for file in $CONF_LIST;do
	reconfig_dnsmasq $file
done


