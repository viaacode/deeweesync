#!/usr/bin/env bash

while getopts "h:r:u:k:p:" opt; do
    case $opt in
        h) DockerHost=$OPTARG
            ;;
        r) AvoTablauRepo=$OPTARG
            ;;
        u) RemoteUser=$OPTARG
            ;;
        k) SSHPrivateKey=$OPTARG
            ;;
        p) MysqlRootPassword=$OPTARG
            ;;
    esac
done

function startdb {
local dbname=$1
local port=$2
local servicename=${dbname/_/-}
local datadir="/home/$RemoteUser/$servicename"
ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
  set -x

  rm -fr init-$dbname
  mkdir init-$dbname
  cd init-$dbname
  git clone $AvoTablauRepo
  # add dbname to db initialization scripts
  for file in avo-tableau/MySQL\ Scripts/$dbname/*.sql
    do sed -e '1 i use $dbname;' "\$file" >\$(basename "\$file") 
  done
  # add named pipe for importing the database as first initialization step
  mkfifo 00-$dbname.sql

  # remove existing container if present
  if docker ps -a | grep -q "$servicename$" ; then
      docker rm -fv "$servicename"
  fi

  # Clean datadir if present
  [ -n "$datadir" ] && [ -d "$datadir" ] && rm -fr "$datadir"/*

  docker run -d --user \$(id -u) --name "$servicename" -p $port:3306 -e MYSQL_ROOT_PASSWORD="$MysqlRootPassword" \
   -v /home/$RemoteUser/init-$dbname:/docker-entrypoint-initdb.d/ \
   -v "$datadir:/var/lib/mysql/" \
   -e SERVICE_NAME="$servicename" mysql:5.6 \
   --innodb_flush_log_at_trx_commit=0 --innodb_log_file_size=128M --skip-innodb_doublewrite \
   --innodb_flush_method=nosync
EOF
}

function mostrecentbackup {
  local dbname=$1
  find /mediasalsa_backup/mysql_backup/ -type f -name "${dbname}-*gz" | grep -v 2015 | sort | tail -1
}

db="sb_testbeeldond"
startdb $db 3306
dump=$(mostrecentbackup $db)
echo "Recovering $dump"
cat $dump | ssh -i $SSHPrivateKey $RemoteUser@$DockerHost \
"(echo 'create database $db; use $db;'; gunzip | sed -r 's/^(\) ENGINE=)InnoDB /\1MyISAM /') >init-$db/00-$db.sql"
if [ $? -eq 0  ]; then
  TIMESTAMP=$(stat -c '%y' $dump)
  ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
     echo "insert into syncs (service, time) \
         values ('${db/_/-}', '$TIMESTAMP') \
         on conflict on constraint syncs_pkey do update set time = \
         '$TIMESTAMP' where syncs.service = '${db/_/-}' ;" \
         | docker exec -i tldb psql -qt -U postgres syncstatus 2>&1
EOF
fi

db="mediamosa"
startdb $db 3307
dump=$(mostrecentbackup $db)
echo "Recovering $dump"
cat $dump | ssh -i $SSHPrivateKey $RemoteUser@$DockerHost \
"(echo 'create database $db;use $db;'; gunzip ) >init-$db/00-$db.sql"
if [ $? -eq 0  ]; then
  TIMESTAMP=$(stat -c '%y' $dump)
  ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
     echo "insert into syncs (service, time) \
         values ('${db/_/-}', '$TIMESTAMP') \
         on conflict on constraint syncs_pkey do update set time = \
         '$TIMESTAMP' where syncs.service = '${db/_/-}' ;" \
         | docker exec -i tldb psql -qt -U postgres syncstatus 2>&1
EOF
fi
