# Security Documentation - IG Edge One

## Security Overview

IG Edge One implements a defense-in-depth security model with multiple layers of protection suitable for ISP edge appliances exposed to the internet.

## Security Layers

### 1. Network Security (UFW Firewall)

#### Firewall Rules
```
Inbound Rules (Allow):
  • SSH:        22/TCP    (Administrative access)
  • DNS:        53/TCP    (DNS queries over TCP)
  • DNS:        53/UDP    (DNS queries over UDP)
  • HTTP:       80/TCP    (LibreSpeed testing)
  • HTTPS:      443/TCP   (Reserved for future TLS)
  • Uptime Kuma:3001/TCP  (Monitoring interface)
  • WireGuard:  51820/UDP (VPN tunnel)
  • WireGuard:  51821/TCP (VPN management)
  • Portainer:  9443/TCP  (Container management)

Default Policy:
  • Inbound:  DENY (all others blocked)
  • Outbound: ALLOW
  • IPv6:     ENABLED
```

#### IPv6 Support
- All rules support both IPv4 and IPv6
- UFW rules are bidirectional for IPv6
- ICMP and ICMPv6 limited to prevent DoS

### 2. Intrusion Detection (Fail2Ban)

#### Protection Mechanisms
- **Monitors**: SSH, Portainer, WireGuard Easy
- **Log Sources**: `/var/log/auth.log`, service logs
- **Action**: Automatic IP address banning

#### Ban Policy
```
Standard Jails:
  • Ban Time:      24 hours (86400 seconds)
  • Find Time:     10 minutes (600 seconds)
  • Max Retries:   5 failed attempts
  • Action:        Ban IP address

Recidive Jail (Repeat Offenders):
  • Ban Time:      7 days (604800 seconds)
  • Find Time:     24 hours
  • Max Retries:   3 previous bans
  • Action:        Aggressive re-banning
```

#### SSH Protection
- Monitors invalid user attempts
- Detects failed password/key authentication
- Blocks connection attempts from suspicious IPs
- Whitelist: localhost (127.0.0.1/8)

### 3. SSH Hardening

#### Default Configuration
```
PermitRootLogin:     prohibit-password (keys preferred)
PubkeyAuthentication: yes (enabled)
PasswordAuthentication: yes (enabled for bootstrap)
Protocol:            2 (only v2)
X11Forwarding:       no
PrintMotd:           yes
Banner:              /etc/ssh/banner
```

#### Post-Installation Recommendations
1. **Generate SSH key pair**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<ip>
   ```

2. **Disable password authentication**
   ```bash
   sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   systemctl restart sshd
   ```

3. **Change default port (optional)**
   ```bash
   sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
   systemctl restart sshd
   ```

### 4. Docker Security

#### Container Isolation
- **No Privileged Mode**: All containers run unprivileged
- **No Host Networking**: Containers use isolated network bridge
- **Network Policy**: Custom bridge (igedge-network)
- **User Namespace**: Containers run as non-root when possible

#### Volume Management
- **Persistent Storage**: Volumes mapped to `/opt/igedge`
- **No Tmpfs**: All data persisted for recovery
- **Permissions**: Proper ownership and file permissions
- **SELinux/AppArmor**: Docker's default security profiles

#### Resource Limits
```yaml
# Consider adding resource limits:
deploy:
  resources:
    limits:
      cpus: '1'
      memory: 512M
    reservations:
      cpus: '0.5'
      memory: 256M
```

### 5. DNS Security (Unbound)

#### DNSSEC Validation
- **Enabled**: Full DNSSEC chain validation
- **Root Anchor**: Updated automatically
- **Logging**: Query validation logged
- **Performance**: Minimal impact on query time

#### Access Control
```
Allowed Networks (defaults):
  • 127.0.0.1/8        (Localhost)
  • 192.168.0.0/16     (Private)
  • 10.0.0.0/8         (Private)
  • 172.16.0.0/12      (Private)
  • ::1/128             (IPv6 localhost)
  
Default: DENY all others
```

#### Cache Security
- **Poisoning Protection**: Query validation
- **Random Query IDs**: Prevents cache poisoning
- **TTL Limits**: Prevents long-lived cached poisoned records
- **Response Rate Limiting**: DoS protection

### 6. Data Protection

#### Backup Security
- **Locations**: `/etc/unbound`, `/opt/igedge`, `/etc/fail2ban`, `/etc/docker`
- **Encryption**: Not encrypted (recommend external encryption)
- **Retention**: 30-day rolling retention
- **Location**: `/opt/igedge/backup/`

#### Recommendations for Production
1. **Encrypt backups**
   ```bash
   gpg --symmetric backup.tar.gz
   ```

2. **Store offsite**
   - Copy to secure backup server
   - Use rsync over SSH
   - Implement 3-2-1 backup strategy

3. **Verify integrity**
   ```bash
   tar -tzf backup.tar.gz | head
   ```

### 7. Logging & Audit Trail

#### Log Locations
```
/var/log/auth.log          # SSH, Fail2Ban, system auth
/var/log/syslog            # System messages
/var/log/unbound/          # DNS queries and validation
/var/log/fail2ban.log      # Intrusion attempts
/var/log/igedge/           # Installation and maintenance
docker logs [container]    # Per-service logs
```

#### Log Retention
- **System Logs**: Configured via logrotate
- **Retention Period**: 30 days (configurable)
- **Rotation**: Daily rotation for large logs
- **Compression**: gzip compression for archived logs

#### Audit Recommendations
1. **Monitor authentication**: `tail -f /var/log/auth.log`
2. **Track Fail2Ban**: `fail2ban-client status`
3. **Review firewall**: `ufw status verbose`
4. **Check services**: `docker compose ps -a`

### 8. Secrets Management

#### Current Implementation
- **Portainer Password**: Generated during installation
- **WireGuard Password**: Set by administrator
- **SSH Keys**: Stored in home directory

#### Security Concerns
⚠️ **Passwords stored in `/docker/.env`** (plaintext)

#### Recommendations
1. **Use environment variable files with restricted permissions**
   ```bash
   chmod 600 docker/.env
   ```

2. **Never commit `.env` to version control**
   - Already in `.gitignore`

3. **Use secrets management tools**
   - Docker Secrets (Swarm mode)
   - External vaults (HashiCorp Vault, etc.)

4. **Rotate credentials regularly**
   - Change Portainer admin password monthly
   - Regenerate WireGuard keys quarterly

### 9. Compliance & Hardening Benchmarks

#### CIS Debian 13 Alignment
- ✅ UFW firewall enabled and configured
- ✅ SSH hardened with key authentication option
- ✅ Fail2Ban configured for brute-force protection
- ✅ Log retention configured
- ✅ Unnecessary services disabled
- ✅ IPv4 forwarding enabled for WireGuard only

#### Recommended Additional Hardening
1. **Kernel parameters**
   ```bash
   echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf
   echo "net.ipv4.conf.all.accept_redirects=0" >> /etc/sysctl.conf
   sysctl -p
   ```

2. **File integrity monitoring**
   ```bash
   apt install aide aide-common
   aideinit
   ```

3. **Intrusion detection**
   ```bash
   apt install suricata
   ```

## Vulnerability Management

### Security Updates
- **Frequency**: Install monthly or as critical updates release
- **Process**: `sudo ./scripts/update.sh`
- **Testing**: Verify in staging before production

### Known Limitations
1. **Password authentication enabled**: Use key-based only in production
2. **Self-signed certificates**: Portainer uses self-signed HTTPS
3. **No WAF/IDS**: Consider external protection
4. **Single point of failure**: No built-in clustering

## Incident Response

### Blocked IP Addresses
```bash
# View banned IPs
sudo fail2ban-client status sshd

# Unban an IP
sudo fail2ban-client set sshd unbanip <IP>
```

### Service Failure Recovery
```bash
# Restart all services
docker compose -f docker/docker-compose.yml restart

# View service logs
docker compose -f docker/docker-compose.yml logs -f [service]

# Reset service
docker compose -f docker/docker-compose.yml down -v
docker compose -f docker/docker-compose.yml up -d
```

### System Recovery
```bash
# Restore from backup
sudo tar -xzf backup/igedge-backup-YYYY-MM-DD.tar.gz -C /

# Verify restored files
ls -la /opt/igedge/
```

## Security Checklist

Before production deployment:
- [ ] Change SSH to key-based authentication
- [ ] Configure external backups
- [ ] Set up log aggregation
- [ ] Enable firewall logging
- [ ] Document security policies
- [ ] Schedule security audits
- [ ] Test backup restoration
- [ ] Document incident response procedures
- [ ] Set up monitoring alerts
- [ ] Review and update Fail2Ban rules

## References

- [Debian Security Handbook](https://www.debian.org/security/)
- [CIS Debian 13 Benchmark](https://www.cisecurity.org/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)