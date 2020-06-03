#!/bin/bash
lssh $1 sudo bash <<<EOF
cat <<<EOIF > /etc/docker/daemon.json
{
  "registry-mirrors": ["http://10.1.1.101:5000"],
  "insecure-registries" : [
    "10.1.1.101:8082","10.1.1.101:5000"
  ]
}
EOIF
systemctl restart docker
EOF
