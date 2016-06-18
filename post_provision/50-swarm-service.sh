#!/bin/bash

[[ ! -f /etc/swarm-node.env ]] && exit 0

. /etc/swarm-node.env

cat <<EOF> /etc/systemd/system/docker.service.d/docker.conf;
[Service]
Environment=DOCKER_OPTS='--insecure-registry=10.0.0.0/8,registry.docker.local -H=0.0.0.0:2376 -H unix:///var/run/docker.sock --cluster-advertise eth0:2376 --cluster-store etcd://127.0.0.1:2379'
EOF

systemctl daemon-reload
systemctl restart docker

docker run -d \
  --name swarm-agent \
  --net=host \
  swarm:latest join \
  --addr=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4/):2376 \
  etcd://127.0.0.1:2379

docker run -d \
  --name swarm-manager \
  --net=host \
  swarm:latest manage \
  etcd://127.0.0.1:2379
