#!/usr/bin/env bash
while getopts "h:d:u:k:" opt; do
    case $opt in
        h) DockerHost=$OPTARG
            ;;
        d) RecoveryArea=$OPTARG
            ;;
        u) RemoteUser=$OPTARG
            ;;
        k) SSHPrivateKey=$OPTARG
            ;;
    esac
done
ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
  [ -d ams ] || mkdir ams
  if docker ps -a | grep -q ams; then
    docker rm -fv ams
  fi
EOF

# Make sure local container is not running
docker stop ams

TIMESTAMP=$(stat -c '%y' $RecoveryArea/../backup.status)
echo "Syncing snapshot taken at $TIMESTAMP"

rsync --inplace -av -e "ssh -i $SSHPrivateKey" \
    --delete \
    $RecoveryArea/ $RemoteUser@$DockerHost:ams

ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
  docker run -d --user \$(id -u) --name ams -p 3308:3306 -v ~/ams:/var/lib/mysql -e SERVICE_NAME=ams mariadb:10.3
  if [ -n '$TIMESTAMP' ]; then
    echo "insert into syncs (service, time) \
         values ('ams', '$TIMESTAMP') \
         on conflict on constraint syncs_pkey do update set time = \
         '$TIMESTAMP' where syncs.service = 'ams' ;" \
         | docker exec -i tldb psql -qt -U postgres syncstatus 2>&1
    fi
EOF

