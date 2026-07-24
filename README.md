# mochimox-docker-lxc

This repo contains scripts to launch LXC containers with Docker preinstalled.

The main script now stops on errors, waits for the container to become ready, and lets you choose the Proxmox storage target instead of assuming `local-lvm`.

If Docker installation still fails for any environment-specific reason, use `docker-install.sh` to install Docker manually inside the container.
You can run it from inside the container after logging in, for example with `bash docker-install.sh` if you copy the script over first.

Steps to create LXC container:

1. Open shell in Proxmox host
2. Enter command:
bash <(curl -s https://raw.githubusercontent.com/MochiTek/mochimox-docker-lxc/main/create-docker-lxc.sh)
3. Fill in the prompts for your LXC spec, including bridge, storage, disk, RAM, swap, and CPU settings
4. If the script reports an error, fix the underlying Proxmox or container issue and rerun it
5. If the container is created but Docker is missing or unhealthy, run:
   systemctl status docker
   systemctl start docker
