#!/bin/bash

set -euo pipefail

trap 'echo "❌ Error on line $LINENO. Aborting." >&2' ERR

apt update
apt install -y ca-certificates curl gnupg lsb-release

# Set up Docker's GPG key and repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

# Install Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Test it
docker run hello-world

echo "✅ Docker installation completed successfully."
