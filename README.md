# mochimox-docker-lxc

This Repo is to store scripts to be able to laucnh LXC containers that has docker preinstalled.

Currently there is a bug with the script where the docker may fail during install. If it does, then run the second script (docker-install.sh) to manually install onto your LXC instance

Steps to create LXC container:

1. Open shell in Proxmox host
2. Enter command:
bash <(curl -s https://raw.githubusercontent.com/MochiTek/mochimox-docker-lxc/main/create-docker-lxc.sh)
3. Fill in the prompts to desired LXC spec
4. If no errors then you are good to go!
5. On error:
   - Check that you can log into the LXC host
   - Check that docker is running
    systemctl status docker
    If avaiable but down then:
    systemctl start docker
