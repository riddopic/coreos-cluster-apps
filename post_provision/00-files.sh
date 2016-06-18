#!/bin/bash

cd /var/lib/apps/post_provision

# login profiles
mkdir -p /etc/profile.d
cp -R etc/profile.d/ /etc/
chmod 644 /etc/profile.d/*
chown root /etc/profile.d/*

# Docker registry credentials
# cp home/core/.dockercfg /home/core/.dockercfg
# chmod 644  /home/core/.dockercfg
# chown core /home/core/.dockercfg
# sudo cp /home/core/.dockercfg /root/.dockercfg

curl -sLO https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
if grep "cfssl_linux-amd64" "SHA256SUMS" | sha256sum -c; then
  mv cfssl_linux-amd64 /opt/bin/cfssl
  chmod +x /opt/bin/cfssljson
else
  echo "The checksum for cfssl did not match!"
fi

curl -sLO https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
if grep "cfssljson_linux-amd64" "SHA256SUMS" | sha256sum -c; then
  mv cfssljson_linux-amd64 /opt/bin/cfssljson
  chmod +x /opt/bin/cfssljson
else
  echo "The checksum for cfssljson did not match!"
fi
