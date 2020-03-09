#!/usr/bin/env bash
# Start an openldap container on a remote vm with a copy of the backup of 
# a local ldap database.
# This script is designed to run after a recovery test of the ldap data. It
# runs on the host where the data has been recovered and pushes the data
# to the remote vm.
# On the remote vm, it creates the following directory structure
#  ldap/
#    init: ldap server configuration
#    data: ldap databases. Structure must match backend definitions in the ldap
#       server configuration
#    docker-openldap: definition of the docker container
# Uses:
#   openldap container: https://github.com/viaacode/docker-openldap.git
#   openldap configuration: https://github.com/viaacode/docker-openldap-deewee.git
# On the remote VM:
#    docker and rsync
#    RemoteUser must be in the docker group

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
  [ -d ldap ] || mkdir ldap
  cd ldap

  # Build or update the docker-openldap container
  if [ -d docker-openldap ]; then
      cd docker-openldap && git pull && cd ..
  else
      git clone https://github.com/viaacode/docker-openldap.git
  fi
  docker build -t openldap:latest docker-openldap

  # Get or update the opebnldap configuration
  if [ -d init ] ; then
      cd init && git pull && git submodule update
  else
      git clone https://github.com/viaacode/docker-openldap-deewee.git init
      cd init && git submodule init && git submodule update
  fi

  # Create data directory
  [ -d data ] || mkdir data
  
  # Remove a running container
  if docker ps -a | grep -q ldap; then
    docker rm -fv ldap
  fi
EOF

# Sync the data
rsync --inplace -av -e "ssh -i $SSHPrivateKey" \
    --exclude '__db.*' --exclude alock --delete-excluded --delete \
    $RecoveryArea/ $RemoteUser@$DockerHost:ldap/data

# Start the container
ssh -i $SSHPrivateKey $RemoteUser@$DockerHost <<EOF
  set -x
  docker run -d --name ldap -e SERVICE_NAME=ldap \
      -u \$(id -u) \
      -v ~/ldap/init/:/docker-entrypoint-init \
      -v ~/ldap/data:/var/lib/ldap \
      openldap:latest
EOF

