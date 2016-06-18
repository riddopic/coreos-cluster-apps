#!/bin/bash

cd /var/lib/apps/post_provision

# login profiles
mkdir -p /etc/profile.d
cp -R etc/profile.d/ /etc/
chmod 644 /etc/profile.d/*
chown root /etc/profile.d/*

# Docker registry credentials
# cp home/core/.dockercfg /home/core/.dockercfg
# chmod 644 /home/core/.dockercfg
# chown core /home/core/.dockercfg
# sudo cp /home/core/.dockercfg /root/.dockercfg
