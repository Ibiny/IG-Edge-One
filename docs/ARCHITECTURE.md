# System Architecture - IG Edge One

## Overview

IG Edge One is a hardened ISP appliance platform designed for edge computing with integrated services for DNS caching, performance monitoring, VPN management, and container orchestration.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Internet                                     │
└────────┬─────────────────────────────────────────────────────┬───┘
         │                                                      │
    ┌────▼────────────────────────────────────────────────────▼────┐
    │              UFW Firewall (Ingress/Egress)                    │
    │  • Deny all inbound (default)                                 │
    │  • Allow specific ports: 22, 53, 80, 443, 3001, 9443         │
    │  • UDP: 51820, 51821 for WireGuard                           │
    └────┬─────────────────────────────────────────────────────┬───┘
         │                                                      │
    ┌────▼──────────────────────────────────────────────────────▼──┐
    │              Fail2Ban Intrusion Detection                     │
    │  • Monitors: SSH, Portainer, WireGuard                        │
    │  • Ban policy: 5 attempts in 10 min = 24h ban                │
    │  • Recidive: 3 bans in 24h = 7 day ban                       │
    └────┬────────────────────────────────────────────────────┬────┘
         │                                                    │
    ┌────▼───────────────────────────────────────────────────▼────┐
    │            Docker Host (Debian 13)                          │
    │  • IPv4 & IPv6 support                                      │
    │  • Timezone: America/Sao_Paulo                              │
    │  • NTP: Chrony synchronization                              │
    │  • Logging: 30-day retention                                │
    └────┬──────────────────────────────────────────────────┬─────┘
         │                                                  │
    ┌────▼──────────────────────────────────────────────────▼────┐
    │         Docker Network: igedge-network (Isolated)         │
    │  • IPv4: 172.20.0.0/16                                    │
    │  • IPv6: 2001:db8:1::/64                                  │
    │  • No privileged containers                               │
    │  • No host networking                                     │
    └────┬───────────────────────────────────────────────┬──────┘
         │                                               │
    ┌────▼──────┐ ┌──────────┐ ┌─────────┐ ┌────────┐ ┌▼──────────┐
    │  Unbound   │ │LibreSpeed│ │ Uptime  │ │  WG    │ │Portainer  │
    │    DNS     │ │          │ │  Kuma   │ │ Easy   │ │           │
    │            │ │ Speed    │ │         │ │ VPN    │ │Container  │
    │ • DNSSEC   │ │ Testing  │ │Monitor- │ │ Mgmt   │ │Management │
    │ • Caching  │ │          │ │ ing     │ │        │ │           │
    │ • Prefetch │ │ Port 80  │ │ Port    │ │Ports   │ │Port 9443  │
    │            │ │          │ │ 3001    │ │51820   │ │           │
    │ Port 53    │ │          │ │         │ │51821   │ │           │
    └───────────┘ └──────────┘ └─────────┘ └────────┘ └───────────┘
         │             │            │          │            │
         └─────────────┴────────────┴──────────┴────────────┘
                        │
                ┌───────▼────────┐
                │ Persistent     │
                │ Volumes        │
                │ /opt/igedge    │
                └────────────────┘
```

## Network Stack

### Firewall (UFW)
- **Default Policy**: Deny all inbound, allow all outbound
- **IPv4/IPv6**: Both supported
- **Rules**: Whitelist-based access control

### Fail2Ban
- **SSH**: Monitor `/var/log/auth.log`
- **Services**: Portainer, WireGuard Easy
- **Ban Duration**: 24 hours standard, 7 days for repeat offenders
- **Threshold**: 5 failed attempts in 10 minutes

### Docker Networking
- **Network**: `igedge-network` (custom bridge)
- **IPv4**: 172.20.0.0/16
- **IPv6**: 2001:db8:1::/64 (ULA prefix)
- **DNS**: Automatic via Unbound (127.0.0.1:53)

## Service Details

### 1. Unbound DNS (Port 53)
- **Caching**: 64MB message cache, 128MB RRset cache
- **Security**: DNSSEC validation enabled
- **Performance**: Prefetch and qname minimization
- **Access Control**: Limited to trusted networks
- **IPv6**: Full support

### 2. LibreSpeed (Port 80)
- **Purpose**: ISP speed testing
- **Default HTTP**: Serves on port 80
- **Storage**: Configuration and results persistence
- **Performance**: Optimized for edge testing

### 3. Uptime Kuma (Port 3001)
- **Monitoring**: Multi-service health checks
- **Notifications**: Email, webhook support
- **Status Pages**: Public availability dashboards
- **Database**: SQLite with persistent storage

### 4. WireGuard Easy (Ports 51820/UDP, 51821/TCP)
- **Protocol**: WireGuard VPN tunneling
- **Management**: Web UI on port 51821
- **Configuration**: Persistent in /opt/igedge/wg-easy
- **Admin**: Password-protected interface

### 5. Portainer (Port 9443)
- **Management**: Docker container orchestration
- **Security**: HTTPS-only with self-signed certificate
- **Access**: Web UI at https://<ip>:9443
- **Admin**: Single admin user with secure password

## Data Persistence

```
/opt/igedge/
├── unbound/
│   ├── config/
│   │   └── unbound.conf
│   ├── root.hints
│   └── data/
├── librespeed/
│   ├── config/
│   └── results/
├── uptime-kuma/
│   └── data/
├── wg-easy/
│   └── wgui/
└── portainer/
    └── data/
```

## Security Model

### Defense in Depth
1. **Firewall (UFW)**: Network perimeter
2. **Fail2Ban**: Brute force protection
3. **Docker Isolation**: Container sandboxing
4. **SSH Hardening**: Key + password auth
5. **DNSSEC**: DNS validation

### No Privileged Operations
- All containers run without `--privileged`
- No host networking used
- Capabilities limited to required functions

## Performance Specifications

| Metric | Configuration |
|--------|---------------|
| DNS Cache | 64MB message + 128MB RRset |
| Prefetch | Enabled for cache hits |
| DNSSEC | Enabled with validation |
| Log Retention | 30 days |
| Backup Retention | 30 days |
| Container Restart | Unless-stopped policy |
| Threads | 4 per DNS resolver |

## Monitoring & Logging

### Log Locations
- `/var/log/igedge/install.log` - Installation log
- `/var/log/auth.log` - SSH and Fail2Ban logs
- Docker logs: `docker compose logs [service]`

### Health Checks
- Docker built-in checks every 30 seconds
- SSH: Port 22 connectivity
- DNS: Query response validation
- HTTP: Service accessibility

## Backup & Recovery

### Backup Scope
- `/etc/unbound` - DNS configuration
- `/opt/igedge` - All application data
- `/etc/fail2ban` - Security policies
- `/etc/docker` - Docker daemon config

### Schedule
- Manual: `./scripts/backup.sh`
- Automatic: 2:00 AM daily (configurable)
- Retention: 30 days rolling window

## Update Strategy

### OS Updates
- `apt update && apt upgrade`
- Applied during `./scripts/update.sh`
- Can be run without service disruption

### Container Updates
- `docker compose pull` - Latest images
- `docker compose up -d` - Recreate with new versions
- Health checks verify service availability

## IPv6 Support

### Network Configuration
- Docker bridge: 2001:db8:1::/64
- Unbound: Listens on :: (all IPv6)
- UFW: IPv6 enabled
- Services: IPv6-ready

### DNS
- A records (IPv4) and AAAA records (IPv6)
- Dual-stack DNS resolution
- IPv6 forwarding enabled in kernel