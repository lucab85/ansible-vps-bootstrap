# Ubuntu VPS bootstrap with Ansible

Bootstrap for an Ubuntu 24.04 KVM VPS intended to run Docker workloads such as
n8n and Medusa. It installs updates, a deploy user, SSH safeguards, UFW, 4 GB
swap, unattended upgrades, Docker Engine/Compose, bounded Docker logs and the
`/opt/apps` directory tree.

## Requirements

- Ansible 2.15+ on your local computer
- Ubuntu 24.04 VPS reachable over SSH
- Initial root access (or adjust `ansible_user` to a sudo-capable account)

## Run

```bash
cp inventory.ini.example inventory.ini
mkdir -p group_vars
cp group_vars/vps.yml.example group_vars/vps.yml
```

Edit `inventory.ini` with the VPS IP and put your **public** SSH key in
`group_vars/vps.yml`. Never paste a private key there.

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook --syntax-check site.yml
ansible all -m ping
ansible-playbook site.yml
```

Open a second terminal and verify login before enabling lock-down:

```bash
ssh deploy@YOUR_VPS_IP
```

Once key login works, change these values in `group_vars/vps.yml` and run the
playbook again:

```yaml
ssh_disable_root_login: true
ssh_disable_password_auth: true
```

## Notes

- Only ports 22, 80 and 443 are opened. Do not publish PostgreSQL or Redis ports.
- Docker-published ports can bypass parts of UFW; bind internal services only to
  Docker networks and expose the reverse proxy on 80/443.
- The Medusa/n8n Docker Compose stack is deployed separately, by hand over SSH,
  not by this playbook — see [`compose/README.md`](compose/README.md) for the
  stack layout and deployment runbook. Application secrets, DNS and backups
  remain outside this repo.
- Reboot once after the first full system upgrade if `/var/run/reboot-required`
  exists.

