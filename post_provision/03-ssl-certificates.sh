#!/bin/bash

# TODO: This should not be done on the hosts...

IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4/)
HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
LOCAL_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/hostname | awk -F "." '{print $1}')
PUBLIC_HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)

mkdir /root/bin

curl -SlO https://pkg.cfssl.org/R1.2/SHA256SUMS

curl -sLO https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
if grep "cfssl_linux-amd64" "SHA256SUMS" | sha256sum -c; then
  mv cfssl_linux-amd64 /root/bin/cfssl
  chmod +x /root/bin/cfssl
else
  echo "The checksum for cfssl did not match!"
  exit 1
fi

curl -sLO https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
if grep "cfssljson_linux-amd64" "SHA256SUMS" | sha256sum -c; then
  mv cfssljson_linux-amd64 /root/bin/cfssljson
  chmod +x /root/bin/cfssljson
else
  echo "The checksum for cfssljson did not match!"
  exit 1
fi

rm -f SHA256SUMS

mkdir /root/cfssl
cd /root/cfssl

# Generate CA
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

cat <<EOF > ca-config.json;
{
  "signing": {
    "default": {
      "expiry": "43800h"
    },
    "profiles": {
      "server": {
        "expiry": "43800h",
        "usages": [
          "signing",
          "key encipherment",
          "server auth"
        ]
      },
      "client": {
        "expiry": "43800h",
        "usages": [
          "signing",
          "key encipherment",
          "client auth"
        ]
      },
      "client-server": {
        "expiry": "43800h",
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ]
      }
    }
  }
}
EOF

cat <<EOF > ca-csr.json;
{
  "CN": "Blue Beluga CA",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "CA",
      "O": "The Blue Beluga",
      "ST": "Palo Alto",
      "OU": "BlueOps"
    }
  ]
}
EOF

# Generate server certificate
#
# server certificate is used by server and verified by client for server
# identity. For example docker server or kube-apiserver.
#
cat <<EOF> server.json;
{
  "CN": "$LOCAL_HOSTNAME",
  "hosts": [
    "$IP",
    "$PUBLIC_HOSTNAME",
    "$LOCAL_HOSTNAME",
    "$HOSTNAME"
  ],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "CA",
      "ST": "Palo Alto"
    }
  ]
}
EOF

# Generate server certificate and private key:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=server server.json | cfssljson -bare server

# Generate client-server certificate
#
# client-server certificate is used by etcd cluster members as they communicate
# with each other in both ways.
#
cat <<EOF> client-server.json;
{
  "CN": "$LOCAL_HOSTNAME",
  "hosts": [
    "$IP",
    "$PUBLIC_HOSTNAME",
    "$LOCAL_HOSTNAME",
    "$HOSTNAME"
  ],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "CA",
      "ST": "Palo Alto"
    }
  ]
}
EOF

# Generate client-server certificate and private key:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client-server client-server.json | cfssljson -bare client-server

# Generate client certificate
#
# client certificate is used to authenticate client by server. For example
# etcdctl, etcd proxy, fleetctl or docker clients.
#
cat <<EOF> client.json;
{
  "CN": "client",
  "hosts": [""],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "C": "US",
      "L": "CA",
      "ST": "Palo Alto"
    }
  ]
}
EOF

# Generate client certificate:
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=client client.json | cfssljson -bare client

cp /root/cfssl/{server.pem,server-key.pem,ca.pem} /etc/docker/
chmod 0600 /etc/docker/server-key.pem

mkdir /root/.docker
chmod 700 /root/.docker
cd /root/.docker
cp /root/cfssl/ca.pem /root/.docker/ca.pem
cp /root/cfssl/client.pem /root/.docker/cert.pem
cp /root/cfssl/client-key.pem /root/.docker/key.pem

mkdir /home/core/.docker
chmod 700 /home/core/.docker
cp /root/cfssl/ca.pem /home/core/.docker/ca.pem
cp /root/cfssl/client.pem /home/core/.docker/cert.pem
cp /root/cfssl/client-key.pem /home/core/.docker/key.pem
chown -R core:core /home/core/.docker

# Make Docker available on a TCP socket on port 2375 for Swarm.
cat <<EOF> /etc/systemd/system/docker-tls-tcp.socket;
[Unit]
Description=Docker Secured Socket for the API

[Socket]
ListenStream=2376
BindIPv6Only=both
Service=docker.service

[Install]
WantedBy=sockets.target
EOF

systemctl enable docker-tls-tcp.socket
systemctl stop docker
systemctl start docker-tls-tcp.socket

cat <<EOF> etc/systemd/system/docker.service.d/10-tls-verify.conf;
[Service]
Environment=DOCKER_OPTS='-H=0.0.0.0:2376 -H unix:///var/run/docker.sock --insecure-registry=10.0.0.0/8,registry.docker.local --bip="172.17.43.1/16" --tlsverify --tlscacert=/etc/docker/ca.pem --tlscert=/etc/docker/server.pem --tlskey=/etc/docker/server-key.pem'
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker.service
