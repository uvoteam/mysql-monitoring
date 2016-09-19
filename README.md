# Mysql/Mariadb monitoring

## Description

Yet another module for mysql monitoring
Supports multiple instances and multi-master replication with low-level discovery
Please, ensure that you are using mysqld that supports multi-source replication, e.g. mysql 5.7 or mariadb 10+

## Requirements

- Credentials in /etc/zabbix/.my.cnf

## Installing
- Create user for monitoring, e.g.
```
GRANT PROCESS, REPLICATION CLIENT ON *.* TO ‘zabbix’@’localhost’
```
- Put mm.sh into /etc/zabbix folder
- Put mm.conf into /etc/zabbix/zabbix_agentd.conf.d/
- Import template to zabbix - mm.xml
- Apply “Template App Mysql Monitoring” template to host
