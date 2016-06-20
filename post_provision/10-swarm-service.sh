#!/bin/bash

[[ ! -f /etc/swarm-node.env ]] && exit 0

. /etc/swarm-node.env

IP_1=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4/)
IP_2=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4/)
DNS_1=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
DNS_2=$(curl -s http://169.254.169.254/latest/meta-data/hostname | awk -F "." '{print $1}')

mkdir -p /home/core/.docker

cd /var/lib/apps/post_provision
bash files/ssl/generate-ssl.sh
cp files/ssl/ca.pem /home/core/.docker/
cp files/ssl/cert.pem /home/core/.docker/
cp files/ssl/key.pem /home/core/.docker/

echo "subjectAltName = @alt_names" >> files/ssl/openssl.cnf
echo "[alt_names]" >> files/ssl/openssl.cnf
echo "IP.1 = ${IP_1}" >> files/ssl/openssl.cnf
echo "IP.2 = ${IP_2}" >> files/ssl/openssl.cnf
echo "DNS.1 = ${DNS_1}" >> files/ssl/openssl.cnf
echo "DNS.2 = ${DNS_2}.xip.io" >> files/ssl/openssl.cnf

openssl req -new \
  -key files/ssl/key.pem \
  -out files/ssl/cert.csr \
  -subj '/CN=docker-client' \
  -config files/ssl/openssl.cnf

openssl x509 -req \
  -in files/ssl/cert.csr \
  -CA files/ssl/ca.pem \
  -CAkey files/ssl/ca-key.pem \
  -CAcreateserial \
  -out files/ssl/cert.pem \
  -days 365 \
  -extensions v3_req \
  -extfile files/ssl/openssl.cnf

mkdir -p /etc/docker/ssl
cp files/ssl/ca.pem /etc/docker/ssl/
cp files/ssl/cert.pem /etc/docker/ssl/
cp files/ssl/key.pem /etc/docker/ssl/

mkdir -p /etc/systemd/system/{docker,swarm-agent,swarm-manager}.service.d

cat <<EOF> /etc/systemd/system/docker.service.d/10-docker-service.conf;
[Service]
Environment="DOCKER_OPTS=-H=0.0.0.0:2376 -H unix:///var/run/docker.sock --tlsverify --tlscacert=/etc/docker/ssl/ca.pem --tlscert=/etc/docker/ssl/cert.pem --tlskey=/etc/docker/ssl/key.pem --cluster-advertise eth0:2376 --cluster-store etcd://127.0.0.1:2379/docker"
EOF

chown -R core:core /home/core/.docker

systemctl daemon-reload
systemctl restart docker.service
systemctl start swarm-agent.service
systemctl start swarm-manager.service
