# Troubleshooting Guide - IG Edge One

## Common Installation Issues

### Installation Script Fails at Phase

#### Error: "System setup script not found"
**Cause**: Directory structure not properly created
**Solution**:
```bash
# Verify directory structure
ls -la scripts/setup/
ls -la docker/

# Ensure scripts are executable
chmod +x scripts/setup/*.sh
chmod +x scripts/*.sh
chmod +x install.sh
```

#### Error: "Docker setup failed"
**Cause**: Docker repository not accessible or old Docker version present
**Solution**:
```bash
# Remove old Docker installation
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Clear Docker cache
sudo rm -rf /var/lib/docker

# Try installation again
sudo ./install.sh
```

#### Error: "UFW not available"
**Cause**: UFW not installed or already running
**Solution**:
```bash
# Check UFW status
sudo ufw status

# If not installed
sudo apt install -y ufw

# Reset UFW rules
sudo ufw reset
sudo ./install.sh
```

### Network Connectivity Issues

#### DNS Not Resolving
**Symptom**: `nslookup google.com` returns "connection refused"
**Diagnosis**:
```bash
# Check if Unbound is running
docker compose -f docker/docker-compose.yml ps unbound

# Check Unbound logs
docker compose -f docker/docker-compose.yml logs unbound | tail -20

# Test DNS connectivity
dig @127.0.0.1 google.com
nslookup google.com 127.0.0.1
```

**Solutions**:
```bash
# Restart Unbound
docker compose -f docker/docker-compose.yml restart unbound

# Verify network connectivity
docker compose -f docker/docker-compose.yml exec unbound ping -c 1 8.8.8.8

# Check configuration
docker compose -f docker/docker-compose.yml exec unbound cat /opt/unbound/etc/unbound/unbound.conf
```

#### Services Not Accessible from External Network
**Symptom**: Cannot reach services on ports 80, 3001, 9443, etc.
**Diagnosis**:
```bash
# Check firewall rules
sudo ufw status verbose

# Check if ports are listening
sudo netstat -tuln | grep LISTEN
# or
sudo ss -tuln | grep LISTEN

# Test local connectivity
curl -v http://localhost
telnet localhost 3001
```

**Solutions**:
```bash
# Verify firewall allows traffic
sudo ufw allow 80/tcp
sudo ufw allow 3001/tcp
sudo ufw allow 9443/tcp

# Check Docker network
docker network inspect igedge-network

# Verify service is running
docker compose -f docker/docker-compose.yml ps
```

## Service-Specific Issues

### LibreSpeed (Port 80)

#### HTTP Service Not Responding
**Diagnosis**:
```bash
docker compose -f docker/docker-compose.yml logs librespeed | tail -30
docker compose -f docker/docker-compose.yml exec librespeed ps aux
```

**Recovery**:
```bash
# Restart service
docker compose -f docker/docker-compose.yml restart librespeed

# Full recreation
docker compose -f docker/docker-compose.yml down librespeed
docker compose -f docker/docker-compose.yml up -d librespeed

# Check health
docker compose -f docker/docker-compose.yml ps librespeed
```

### Uptime Kuma (Port 3001)

#### Database Corruption
**Symptom**: Frequent crashes or won't start
**Solution**:
```bash
# Backup existing database
cp -r /opt/igedge/uptime-kuma /opt/igedge/uptime-kuma.backup

# Remove corrupted database
rm -rf /opt/igedge/uptime-kuma/*

# Restart (will initialize fresh)
docker compose -f docker/docker-compose.yml restart uptime-kuma

# Restore from backup if needed
cp -r /opt/igedge/uptime-kuma.backup/* /opt/igedge/uptime-kuma/
docker compose -f docker/docker-compose.yml restart uptime-kuma
```

### WireGuard Easy (Ports 51820/UDP, 51821/TCP)

#### VPN Not Connecting
**Diagnosis**:
```bash
# Check WireGuard logs
docker compose -f docker/docker-compose.yml logs wg-easy | tail -50

# Verify UDP port is open
sudo ss -tuln | grep 51820

# Check WireGuard interface
docker compose -f docker/docker-compose.yml exec wg-easy wg show
```

**Solutions**:
```bash
# Ensure UFW allows WireGuard
sudo ufw allow 51820/udp
sudo ufw allow 51821/tcp

# Restart service
docker compose -f docker/docker-compose.yml restart wg-easy

# Check firewall doesn't block UDP
sudo sysctl net.ipv4.conf.all.rp_filter
# Should return 0 or 1 (not 2)
```

### Portainer (Port 9443)

#### Certificate Errors
**Symptom**: "HTTPS certificate not valid"
**Solution**:
```bash
# Certificates are self-signed, accept in browser
# Or access via IP address directly

# Regenerate certificate if corrupted
rm -rf /opt/igedge/portainer/data/portainer.crt
rm -rf /opt/igedge/portainer/data/portainer.key
docker compose -f docker/docker-compose.yml restart portainer
```

#### Cannot Login
**Cause**: Wrong credentials or database issue
**Solution**:
```bash
# Reset Portainer (will prompt for new password on first login)
docker compose -f docker/docker-compose.yml down portainer
rm -rf /opt/igedge/portainer/data/portainer.db
docker compose -f docker/docker-compose.yml up -d portainer

# Access at https://<ip>:9443 and set new password
```

## Docker Issues

### Container Won't Start

**General Diagnostics**:
```bash
# Check service status
docker compose -f docker/docker-compose.yml ps

# View detailed logs
docker compose -f docker/docker-compose.yml logs -f [service-name]

# Inspect service configuration
docker compose -f docker/docker-compose.yml config | grep -A 50 "[service-name]:"

# Check Docker daemon logs
journalctl -u docker -n 50
```

**Recovery Steps**:
```bash
# 1. Stop all services
docker compose -f docker/docker-compose.yml down

# 2. Verify volumes exist
ls -la /opt/igedge/

# 3. Restart services
docker compose -f docker/docker-compose.yml up -d

# 4. Check status
docker compose -f docker/docker-compose.yml ps
```

### Out of Disk Space

**Diagnosis**:
```bash
# Check disk usage
df -h /

# Check Docker disk usage
docker system df

# Find large images
docker images --format "table {{.Repository}}\t{{.Size}}"
```

**Cleanup**:
```bash
# Remove unused containers, networks, images
docker system prune -a

# Remove unused volumes
docker volume prune

# Check disk again
df -h /
```

### Network Issues

**DNS not working in containers**:
```bash
# Verify network
docker network inspect igedge-network

# Test from container
docker compose -f docker/docker-compose.yml exec [service] nslookup google.com
docker compose -f docker/docker-compose.yml exec [service] dig @8.8.8.8 google.com
```

**No internet from container**:
```bash
# Check host network connectivity
ping -c 1 8.8.8.8

# Check container connectivity
docker compose -f docker/docker-compose.yml exec [service] ping -c 1 8.8.8.8

# Test DNS specifically
docker compose -f docker/docker-compose.yml exec [service] ping -c 1 unbound
```

## Fail2Ban Issues

### IP Addresses Not Being Banned

**Verification**:
```bash
# Check Fail2Ban status
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd

# View recent bans
sudo tail -f /var/log/fail2ban.log

# Check configuration
cat /etc/fail2ban/jail.local
```

**Enable Logging**:
```bash
# Increase verbosity
sudo fail2ban-client set loglevel 4
sudo systemctl restart fail2ban

# Tail logs to watch
sudo tail -f /var/log/fail2ban.log
```

### False Positives / Legitimate IPs Banned

**Unban an IP**:
```bash
# Unban specific IP from jail
sudo fail2ban-client set sshd unbanip <IP_ADDRESS>

# Unban from all jails
sudo fail2ban-client unban <IP_ADDRESS>

# Verify unbanned
sudo fail2ban-client status sshd
```

**Whitelist IPs**:
```bash
# Edit jail configuration
sudo nano /etc/fail2ban/jail.local

# Add to [DEFAULT] section:
ignoreip = 127.0.0.1/8 ::1 <YOUR_IP>

# Restart
sudo systemctl restart fail2ban
```

## Firewall Issues

### Cannot Access Services

**Check UFW Rules**:
```bash
# View all rules
sudo ufw status verbose

# Check specific port
sudo ufw show raw | grep -i 80
sudo ufw show raw6 | grep -i 80
```

**Add Missing Rules**:
```bash
# Add rule
sudo ufw allow 80/tcp comment "HTTP"

# Verify
sudo ufw status numbered
```

### IPv6 Not Working

**Enable IPv6 in UFW**:
```bash
# Edit configuration
sudo nano /etc/default/ufw

# Change: IPV6=no to IPV6=yes
IPV6=yes

# Reload
sudo ufw reload

# Verify
sudo ufw status verbose
```

## Backup and Recovery

### Backup Failed

**Diagnostics**:
```bash
# Check backup directory
ls -la /opt/igedge/backup/

# Check disk space
df -h /opt/igedge/

# Try manual backup
sudo tar -czf /tmp/test-backup.tar.gz /opt/igedge 2>&1 | head -20
```

**Troubleshoot**:
```bash
# Ensure backup directory exists
sudo mkdir -p /opt/igedge/backup

# Check permissions
sudo chown root:root /opt/igedge/backup
sudo chmod 755 /opt/igedge/backup

# Run backup manually
sudo ./scripts/backup.sh
```

### Cannot Restore Backup

**Verification**:
```bash
# Check backup integrity
tar -tzf backup/igedge-backup-*.tar.gz | head -20

# Verify tarball
tar -tzf backup/igedge-backup-*.tar.gz > /dev/null && echo "Valid" || echo "Corrupt"
```

**Restore Steps**:
```bash
# Stop services
docker compose -f docker/docker-compose.yml down

# Restore backup
sudo tar -xzf backup/igedge-backup-YYYY-MM-DD.tar.gz -C /

# Restart services
docker compose -f docker/docker-compose.yml up -d

# Verify
docker compose -f docker/docker-compose.yml ps
```

## Logs and Debugging

### View System Logs
```bash
# Installation log
tail -f /var/log/igedge/install.log

# System authentication
tail -f /var/log/auth.log

# Docker logs
docker logs -f [container-id]

# Service-specific logs
docker compose -f docker/docker-compose.yml logs -f [service]
```

### Collect Diagnostic Information
```bash
# System info
uname -a
lsb_release -ds

# Network configuration
ip addr show
ip route show

# Docker info
docker info
docker network ls

# Service status
docker compose -f docker/docker-compose.yml ps -a

# Available disk/memory
df -h
free -h

# Export diagnostics to file
{
    echo "=== System ==="
    uname -a
    echo "=== Disk ==="
    df -h
    echo "=== Memory ==="
    free -h
    echo "=== Docker ==="
    docker ps -a
    echo "=== Services ==="
    docker compose -f docker/docker-compose.yml ps
    echo "=== UFW ==="
    sudo ufw status verbose
    echo "=== Fail2Ban ==="
    sudo fail2ban-client status
} > diagnostics.txt
```

## Getting Help

1. **Check logs first**: `tail -f /var/log/igedge/install.log`
2. **Review documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md) and [SECURITY.md](SECURITY.md)
3. **Test connectivity**: Use `docker compose logs [service]`
4. **Report issues**: Include diagnostics from above
5. **Contact support**: Open an issue on GitHub with diagnostics attached