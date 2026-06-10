# IG Edge One - ISP Appliance Hardening

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Debian](https://img.shields.io/badge/Debian-13-A81D33?logo=debian)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker)](https://www.docker.com/)

## Overview

IG Edge One is an automated, hardened ISP appliance installation suite for Debian 13. It provides a complete, production-ready edge computing platform with integrated DNS caching, performance monitoring, VPN management, and container orchestration.

**Installation:** Single command - `sudo ./install.sh`

### Services Included

| Service | Port | Purpose |
|---------|------|----------|
| **LibreSpeed** | 80/TCP | Speed Testing & Default HTTP Service |
| **Unbound DNS** | 53/TCP, 53/UDP | DNS Caching with DNSSEC |
| **Uptime Kuma** | 3001/TCP | Monitoring & Status Pages |
| **WireGuard Easy** | 51820/UDP, 51821/TCP | VPN Management |
| **Portainer** | 9443/TCP | Container Management |
| **SSH** | 22/TCP | Secure Shell Access |

## Pre-Installation Requirements

- **OS:** Debian 13 (fully updated)
- **Hardware:** Minimum 1GB RAM, 10GB storage
- **Network:** Static IP or DHCP reservation recommended
- **Access:** Root or sudo privileges
- **Internet:** Active connection during installation

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/Ibiny/IG-Edge-One.git
cd IG-Edge-One
chmod +x install.sh
```

### 2. Run Installation
```bash
sudo ./install.sh
```

### 3. Follow Interactive Prompts
- Enter public IPv4 address
- Enter hostname for the appliance
- Set WireGuard admin password
- Review configuration summary

### 4. Wait for Completion
The installer will automatically:
- ✅ Update system packages
- ✅ Install Docker Engine
- ✅ Configure UFW firewall
- ✅ Deploy all services
- ✅ Verify service health
- ✅ Display access credentials

## Post-Installation

After successful installation, access services at:

- **Portainer:** `https://<your-ip>:9443`
- **Uptime Kuma:** `http://<your-ip>:3001`
- **LibreSpeed:** `http://<your-ip>`
- **SSH:** `ssh root@<your-ip>` (port 22)

**Default Credentials:**
- SSH: User `root` with password authentication enabled
- Portainer: Random password displayed at installation completion
- WireGuard: Admin password set during installation
- Unbound DNS: No authentication (firewall-protected)

## Security Features

### Implemented Hardening

- **SSH:** Password and key authentication (keys recommended for production)
- **Firewall:** UFW with strict ingress/egress rules
- **Fail2Ban:** 24-hour IP bans after 5 failed attempts in 10 minutes
- **Docker:** 
  - No privileged containers
  - No host networking
  - Persistent volumes only
  - Custom isolated network
- **DNS:** DNSSEC validation, caching, prefetch enabled
- **Logging:** Centralized rotation with 30-day retention

### Future Security Recommendations

- ⚠️ **SSH:** Migrate to key-based authentication only
- ⚠️ **DNS:** Configure access lists for untrusted networks
- ⚠️ **TLS:** Implement certificate management for HTTPS
- ⚠️ **Monitoring:** Set up external log aggregation

## Maintenance Scripts

### Automatic Updates
```bash
sudo ./scripts/update.sh
```
Updates OS packages and all Docker containers.

### Backup Data
```bash
sudo ./scripts/backup.sh
```
Backs up configurations and data with 30-day retention.

## Directory Structure

```
IG-Edge-One/
├── install.sh                 # Main installation script
├── README.md                  # This file
├── LICENSE                    # MIT License
├── docker/
│   ├── docker-compose.yml     # Service definitions
│   └── .env.example           # Environment variables template
├── unbound/
│   ├── unbound.conf           # DNS configuration
│   ├── root.hints             # Root nameservers
│   └── configs/
│       └── access-control.conf
├── scripts/
│   ├── setup/
│   │   ├── system-setup.sh    # OS hardening & packages
│   │   ├── firewall-setup.sh  # UFW configuration
│   │   ├── docker-setup.sh    # Docker Engine installation
│   │   ├── fail2ban-setup.sh  # Intrusion protection
│   │   └── health-check.sh    # Service verification
│   ├── update.sh              # Update automation
│   ├── backup.sh              # Backup automation
│   └── helpers/
│       ├── colors.sh          # Output formatting
│       └── logging.sh         # Log utilities
├── fail2ban/
│   ├── jail.local             # Fail2Ban configuration
│   └── filters/
│       ├── ssh.conf
│       ├── portainer.conf
│       └── wg-easy.conf
├── config/
│   ├── sshd_config            # SSH configuration
│   ├── ufw-rules.txt          # Firewall rules
│   └── chrony.conf            # NTP configuration
├── docs/
│   ├── ARCHITECTURE.md        # System architecture
│   ├── SECURITY.md            # Security details
│   ├── TROUBLESHOOTING.md     # Common issues
│   └── API.md                 # Service APIs
├── backup/                    # Backup destination
└── .gitignore                 # Git ignore rules
```

## Configuration

### Environment Variables

Configure services via `docker/.env`:

```bash
# IPv4 and IPv6
IPV4_ADDRESS=YOUR_PUBLIC_IPv4
IPV6_ADDRESS=YOUR_PUBLIC_IPv6 (optional)

# Hostname
HOSTNAME=igedge-one

# Credentials
PORTAINER_PASSWORD=generated-randomly
WG_ADMIN_PASSWORD=your-secure-password

# DNS
DNS_CACHE_SIZE=64m
DNS_RRSET_CACHE=128m
```

### Firewall Rules

Edit `config/ufw-rules.txt` to modify port access. Rules are applied during installation.

### Fail2Ban Protection

Customize `fail2ban/jail.local`:
- Ban time: 24 hours
- Find time: 10 minutes
- Max retries: 5 attempts

## Troubleshooting

### Services Not Starting
```bash
docker compose -f docker/docker-compose.yml logs -f
```

### Firewall Issues
```bash
sudo ufw status verbose
```

### DNS Resolution
```bash
nslookup google.com 127.0.0.1
```

### Fail2Ban Status
```bash
sudo fail2ban-client status
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed solutions.

## Updating System

Run weekly or as needed:
```bash
sudo ./scripts/update.sh
```

This performs:
- `apt update && apt upgrade`
- Docker image updates
- Service health verification

## Backup & Recovery

Automatic backups every day at 2 AM:
```bash
# Manual backup
sudo ./scripts/backup.sh

# Restore from backup
sudo tar -xzf backup/igedge-backup-YYYY-MM-DD.tar.gz -C /
```

Backed up items:
- `/etc/unbound/`
- `/opt/igedge/`
- `/docker/` configuration
- `/etc/fail2ban/`

## Monitoring

### Service Health Status
After installation or anytime:
```bash
docker compose -f docker/docker-compose.yml ps
```

### Real-time Logs
```bash
docker compose -f docker/docker-compose.yml logs -f [service-name]
```

### Performance Metrics
Access **Portainer** at `https://<your-ip>:9443` for detailed metrics.

## Credentials & Access

### SSH Access
```bash
ssh root@<your-ip>
# or with key
ssh -i ~/.ssh/id_rsa root@<your-ip>
```

### Portainer Access
- URL: `https://<your-ip>:9443`
- Username: `admin`
- Password: *(displayed at installation completion)*

### WireGuard Management
- URL: `http://<your-ip>:51821`
- Password: *(set during installation)*

## Performance Specifications

| Metric | Value |
|--------|-------|
| DNS Cache | 64MB |
| DNS RRset Cache | 128MB |
| Docker Network | Custom `igedge-network` |
| Log Retention | 30 days |
| Backup Retention | 30 days |
| DNS Prefetch | Enabled |
| DNSSEC | Enabled |

## Support & Issues

- **Bug Reports:** [GitHub Issues](https://github.com/Ibiny/IG-Edge-One/issues)
- **Documentation:** [Docs Directory](docs/)
- **Security Issues:** Report privately to maintainers

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## Version History

- **v1.0.0** (2026-06-10) - Initial release
  - Automated installation
  - Full service integration
  - Security hardening
  - Backup & update scripts

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Submit a pull request

## Roadmap

- [ ] Web dashboard for service management
- [ ] Automated certificate management
- [ ] Log aggregation service
- [ ] Advanced monitoring dashboards
- [ ] Multi-site replication
- [ ] Hardware RAID support
- [ ] Custom DNS records interface

## Support

For questions or issues:
- Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- Review [ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Open an issue on GitHub

---

**IG Service Technology** | Hardened Edge Computing Platform