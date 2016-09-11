#!/usr/bin/env bash

hostname=$(hostname -f)

get_mysqld_sockets() {
	ps uaxwww | grep -E 'mysqld.+--socket' | grep -Eo '[\/a-z-]+\.sock+'
}

check_alive() {
	mysqladmin --defaults-extra-file=/etc/zabbix/.my.cnf -S ${1} ping >/dev/null 2>&1
	socket_alive=$?
}

send_to_zabbix() {
	zabbix_sender -T -c /etc/zabbix/zabbix_agentd.conf -i "${1}" > /tmp/mm.zabbix_sender.log 2>&1
}

format_data_out() {
  local _name=$1
  cat | awk 'BEGIN { check=0; count=0; array[0]=0; } {
	  array[count]=$1;
	  count=count+1;
	}
	END {
	  printf( "{\n\t\"data\":[\n" );
	  for(i=0;i<count;++i) {
		printf("\t\t{\n\t\t\t\"{'${_name}'}\":\"%s\"}", array[i]);
		if(i+1<count){ printf(",\n"); }
	  }
	  printf("]}\n");
	}'
}

get_slave_data() {
	socket=${1}
	param=${2}
	replica=${3:-main}
	if [[ "${replica}" == main ]]
	then
		result=$(mysql --defaults-extra-file=/etc/zabbix/.my.cnf -S ${socket} -e"show all slaves status\G" | grep ${param} | cut -d':' -f2 )
	else
		result=$(mysql --defaults-extra-file=/etc/zabbix/.my.cnf -S ${socket} -e"show slave \"${replica}\" status\G" | grep ${param} | cut -d':' -f2 )
	fi
	echo ${result} | sed 's/Yes/0/;s/No/1/;s/Connecting/1/'
}

update_alive_instances() {
	timestamp=$(date +'%s')
	rm -f /tmp/mm.alive_instances.dat

	for socket in $(get_mysqld_sockets); do
		check_alive ${socket}
		instance=$(echo $socket | cut -d'/' -f5 | grep -Eo 'mysql[-a-z]+')
		echo "${hostname} mm.instance.alive[${instance}] ${timestamp} $socket_alive" >> /tmp/mm.alive_instances.dat~
	done

	mv /tmp/mm.alive_instances.dat~ /tmp/mm.alive_instances.dat
	send_to_zabbix /tmp/mm.alive_instances.dat && echo 1 || echo 0
}


discover_instances() {
	get_mysqld_sockets \
	  | cut -d'/' -f5 | grep -Eo 'mysql[-a-z]+' \
	  | format_data_out '#INSTANCE'
}

discover_replicas() {
	for socket in $(get_mysqld_sockets) ; do
		instance=$(echo $socket | cut -d'/' -f5 | grep -Eo 'mysql[-a-z]+')
		replicas=$(get_slave_data ${socket} Connection_name)
		for replica in ${replicas:-main}; do
			echo "${instance}"_"${replica}";
		done
	done | format_data_out '#REPLICA'
}

update_extended_status() {
	timestamp=$(date +'%s')
	rm -f /tmp/mm.extended_status.dat

	for socket in $(get_mysqld_sockets)
	do
		check_alive ${socket}
		instance=$(echo $socket | cut -d'/' -f5 | grep -Eo 'mysql[-a-z]+')
		mysql --defaults-extra-file=/etc/zabbix/.my.cnf -S ${socket} -e 'show GLOBAL status' \
			| tail -n+2 \
			| awk "{if (\$2 != \"\") print \"${hostname} mm.mysql.\" \$1 \"[${instance}]\"\" ${timestamp} \" \$2}" \
			| grep -i -f /etc/zabbix/mm.items >> /tmp/mm.extended_status.dat~
	done

	mv /tmp/mm.extended_status.dat~ /tmp/mm.extended_status.dat
	send_to_zabbix /tmp/mm.extended_status.dat
	echo 1
}

update_replication_status() {
	rm -f /tmp/mm.replication_status.dat
	timestamp=$(date +'%s')

	for socket in $(get_mysqld_sockets)
	do
		instance=$(echo $socket | cut -d'/' -f5 | grep -Eo 'mysql[-a-z]+')
		replicas=$(get_slave_data ${socket} Connection_name)
		for replica in ${replicas:-main}
		do
			SBM=$(get_slave_data ${socket} "Seconds_Behind_Master" ${replica})
			SIR=$(get_slave_data ${socket} "Slave_IO_Running" ${replica})
			SSR=$(get_slave_data ${socket} "Slave_SQL_Running" ${replica})
			echo "${hostname} mm.Seconds_Behind_Master[${instance}_${replica}] ${timestamp} ${SBM/NULL/0}" >> /tmp/mm.replication_status.dat~
			echo "${hostname} mm.Slave_IO_Running[${instance}_${replica}] ${timestamp} ${SIR}" >> /tmp/mm.replication_status.dat~
			echo "${hostname} mm.Slave_SQL_Running[${instance}_${replica}] ${timestamp} ${SSR}" >> /tmp/mm.replication_status.dat~
		done
	done

	mv /tmp/mm.replication_status.dat~ /tmp/mm.replication_status.dat
	send_to_zabbix /tmp/mm.replication_status.dat && echo 1 || echo 0
}

parse_args()
{
	case "$1" in
		discover_instances \
		| discover_replicas \
		| update_alive_instances \
		| update_replication_status \
		| update_extended_status )
		  $1
		  ;;

		-h | --help | --usage )
		  exit 0
		  ;;
		*)
		  echo "$0: error - unrecognized option \""${1}"\""
		  exit 1
		  ;;
	esac
}

parse_args "$@"

# vim: noet ts=4
