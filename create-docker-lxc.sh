#!/bin/bash

set -euo pipefail

trap 'echo "❌ Error on line $LINENO. Aborting." >&2' ERR

# === Ask for settings ===
read -p "Container ID (e.g. 200): " CTID
read -p "Hostname (e.g. mochixxx): " HOSTNAME
while true; do
    read -sp "Enter root password: " PASSWORD && echo
    read -sp "Confirm root password: " PASSWORD_CONFIRM && echo
    if [ "$PASSWORD" = "$PASSWORD_CONFIRM" ]; then
        break
    else
        echo "❌ Passwords do not match. Please try again."
    fi
done
read -p "Static IP address (e.g. 192.168.0.110): " IP
read -p "Gateway (e.g. 192.168.0.1): " GATEWAY
read -p "Bridge (default: vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}
echo "Storage backend:"
echo "  1) local-lvm"
echo "  2) local-zfs"
read -p "Choose storage [1-2] (default: 1): " STORAGE_CHOICE
case "${STORAGE_CHOICE:-1}" in
  1) STORAGE="local-lvm" ;;
  2) STORAGE="local-zfs" ;;
  *)
    echo "❌ Invalid storage choice. Please choose 1 or 2." >&2
    exit 1
    ;;
esac
read -p "Disk size in GB (default: 8): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-8}
read -p "RAM in MB (default: 1024): " RAM_MB
RAM_MB=${RAM_MB:-1024}
read -p "Swap in MB (default: 512): " SWAP_MB
SWAP_MB=${SWAP_MB:-512}
read -p "CPU cores (default: 2): " CORES
CORES=${CORES:-2}
TEMPLATE=""
TEMPLATE_DIR="/var/lib/vz/template/cache"
TEMPLATE_FALLBACK="debian-12-standard_12.7-1_amd64.tar.zst"

if command -v pveam >/dev/null 2>&1; then
  pveam update >/dev/null 2>&1 || true
  TEMPLATE=$(pveam available --section system 2>/dev/null | \
    grep -Eo 'debian-12-standard_[^[:space:]]+_amd64\.tar\.zst' | \
    sort -V | tail -n1 || true)
fi

if [ -z "$TEMPLATE" ]; then
  TEMPLATE="$TEMPLATE_FALLBACK"
fi

TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE"

echo -e "\n🚀 Creating Docker-ready LXC container $CTID..."
echo "📦 Using template: $TEMPLATE"

if ! pvesm status | awk 'NR > 1 {print $1}' | grep -Fxq "$STORAGE"; then
  echo "❌ Storage '$STORAGE' is not available on this Proxmox host." >&2
  exit 1
fi

# Download template if missing
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "⬇️  Downloading Debian 12 template..."
  if command -v pveam >/dev/null 2>&1; then
    pveam download local "$TEMPLATE" >/dev/null 2>&1 || true
  fi

  if [ ! -f "$TEMPLATE_PATH" ]; then
    if command -v wget >/dev/null 2>&1; then
      wget "https://download.proxmox.com/images/system/$TEMPLATE" -O "$TEMPLATE_PATH"
    else
      curl -fSL "https://download.proxmox.com/images/system/$TEMPLATE" -o "$TEMPLATE_PATH"
    fi
  fi
fi

# Verify template archive integrity before use.
if command -v zstd >/dev/null 2>&1; then
  if ! zstd -t "$TEMPLATE_PATH" >/dev/null 2>&1; then
    echo "❌ Template archive appears corrupted: $TEMPLATE_PATH" >&2
    echo "   Delete the file and rerun the script to download it again." >&2
    exit 1
  fi
else
  echo "⚠️  'zstd' is not available, skipping template integrity check."
fi

# Create LXC
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$HOSTNAME" \
  --password "$PASSWORD" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --storage "$STORAGE" \
  --memory "$RAM_MB" \
  --swap "$SWAP_MB" \
  --cores "$CORES" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=$IP/24,gw=$GATEWAY" \
  --features nesting=1,keyctl=1 \
  --unprivileged 0 \
  --ostype debian \
  --arch amd64

# Apply Docker-compatible config
if [ ! -f "/etc/pve/lxc/${CTID}.conf" ]; then
  echo "❌ Container config was not created. Aborting." >&2
  exit 1
fi

cat <<EOF >> "/etc/pve/lxc/${CTID}.conf"
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop:
EOF

# Start and wait
pct start "$CTID"

echo "⏳ Waiting for container to become ready..."
for _ in {1..30}; do
  if pct exec "$CTID" -- true >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! pct exec "$CTID" -- true >/dev/null 2>&1; then
  echo "❌ Container did not become ready in time." >&2
  exit 1
fi

# === Install Docker ===
echo "🐳 Installing Docker inside container..."
pct exec "$CTID" -- bash <<'EOF'
apt update
apt install -y ca-certificates curl gnupg lsb-release apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Optional: enable and start Docker service
systemctl enable docker
systemctl start docker

# Test Docker
docker run hello-world || exit 1
EOF

echo -e "\n✅ Docker is ready in container $CTID!"
