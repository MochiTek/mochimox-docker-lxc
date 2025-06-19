#!/bin/bash

# === Ask for settings ===
read -p "Container ID (e.g. 200): " CTID
read -p "Hostname (e.g. mochixxx): " HOSTNAME
read -sp "Root password: " PASSWORD && echo
read -p "Static IP address (e.g. 192.168.0.110): " IP
read -p "Gateway (e.g. 192.168.0.1): " GATEWAY
read -p "Bridge (default: vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}
read -p "Disk size in GB (default: 8): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-8}
read -p "RAM in MB (default: 1024): " RAM_MB
RAM_MB=${RAM_MB:-1024}
read -p "Swap in MB (default: 512): " SWAP_MB
SWAP_MB=${SWAP_MB:-512}
read -p "CPU cores (default: 2): " CORES
CORES=${CORES:-2}
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

echo -e "\n🚀 Creating Docker-ready LXC container $CTID..."

# Download template if missing
if [ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
  echo "⬇️  Downloading Debian 12 template..."
  wget -q https://downloads.proxmox.com/images/system/$TEMPLATE -O /var/lib/vz/template/cache/$TEMPLATE
fi

# Create LXC
pct create $CTID /var/lib/vz/template/cache/$TEMPLATE \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --rootfs local-lvm:${DISK_SIZE} \
  --storage local-lvm \
  --memory $RAM_MB \
  --swap $SWAP_MB \
  --cores $CORES \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP/24,gw=$GATEWAY \
  --features nesting=1,keyctl=1 \
  --unprivileged 0 \
  --ostype debian \
  --arch amd64

# Apply Docker-compatible config
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop:
EOF

# Start and wait
pct start $CTID
sleep 5

# Install Docker
echo "🐳 Installing Docker inside container..."
pct exec $CTID -- bash -c "
apt update &&
apt install -y ca-certificates curl gnupg lsb-release &&
install -m 0755 -d /etc/apt/keyrings &&
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
chmod a+r /etc/apt/keyrings/docker.gpg &&
echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable' > /etc/apt/sources.list.d/docker.list &&
apt update &&
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# Test Docker
pct exec $CTID -- docker run hello-world

echo -e "\n✅ Docker is ready in container $CTID!"
