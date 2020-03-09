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

docker stop ams

rsync --inplace -av -e "ssh -i $SSHPrivateKey" \
    --delete \
    $RecoveryArea/ $RemoteUser@$DockerHost:ams

ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
  docker run -d --user \$(id -u) --name ams -p 3308:3306 -v ~/ams:/var/lib/mysql -e SERVICE_NAME=ams mariadb:10.3
EOF

