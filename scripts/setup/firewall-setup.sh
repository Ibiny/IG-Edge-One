#!/bin/bash

################################################################################
# IG Edge One - Firewall Setup Script (UFW)
# Phase 3: Configure UFW firewall with optimal rules for ISP appliance
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/logging.sh"

print_header "Firewall Setup - Phase 3"

echo -e "${BLUE}Configuring UFW firewall...${NC}\n"

# Reset UFW to factory defaults (non-interactive)
print_step 1 "Initializing UFW firewall"
ufw --force reset || print_warning "UFW reset may have already been performed"
print_success "UFW initialized"

# Set default policies
print_step 2 "Setting default firewall policies"
ufw default deny incoming || print_warning "Default incoming policy may already be set"
ufw default allow outgoing || print_warning "Default outgoing policy may already be set"
print_success "Default policies configured"

# Allow SSH (critical for remote access)
print_step 3 "Allowing SSH access"
ufw allow 22/tcp || print_warning "SSH rule may already exist"
print_success "SSH port 22 allowed"

# Allow DNS (Unbound)
print_step 4 "Allowing DNS services"
ufw allow 53/tcp || print_warning "DNS TCP rule may already exist"
ufw allow 53/udp || print_warning "DNS UDP rule may already exist"
print_success "DNS ports allowed (TCP/UDP 53)"

# Allow HTTP (LibreSpeed)
print_step 5 "Allowing HTTP traffic"
ufw allow 80/tcp || print_warning "HTTP rule may already exist"
print_success "HTTP port 80 allowed"

# Allow HTTPS (Portainer, potential future services)
print_step 6 "Allowing HTTPS traffic"
ufw allow 443/tcp || print_warning "HTTPS rule may already exist"
print_success "HTTPS port 443 allowed"

# Allow Uptime Kuma
print_step 7 "Allowing Uptime Kuma access"
ufw allow 3001/tcp || print_warning "Uptime Kuma rule may already exist"
print_success "Uptime Kuma port 3001 allowed"

# Allow WireGuard
print_step 8 "Allowing WireGuard VPN"
ufw allow 51820/udp || print_warning "WireGuard UDP rule may already exist"
ufw allow 51821/tcp || print_warning "WireGuard TCP rule may already exist"
print_success "WireGuard ports allowed (UDP 51820, TCP 51821)"

# Allow Portainer (HTTPS management)
print_step 9 "Allowing Portainer management interface"
ufw allow 9443/tcp || print_warning "Portainer rule may already exist"
print_success "Portainer port 9443 allowed"

# Rate limiting on SSH to prevent brute force
print_step 10 "Applying rate limiting to SSH"
ufw limit 22/tcp || print_warning "SSH rate limit may already be applied"
print_success "Rate limiting applied to SSH"

# Enable UFW
print_step 11 "Enabling UFW firewall"
ufw --force enable || print_warning "UFW may already be enabled"
print_success "UFW firewall enabled"

# Display firewall status
print_step 12 "Verifying firewall configuration"
echo ""
echo -e "${CYAN}Current UFW Rules:${NC}"
ufw status verbose
echo ""

# Configure UFW logging
print_step 13 "Configuring UFW logging"
ufw logging on || print_warning "UFW logging may already be enabled"
ufw logging medium || print_warning "UFW logging level may already be set"
print_success "UFW logging enabled at medium level"

# Additional security settings via iptables if needed
print_step 14 "Applying additional network security rules"

# Prevent IP spoofing
if [[ ! -f /etc/network/if-pre-up.d/spoofprotect ]]; then
    cat > /etc/network/if-pre-up.d/spoofprotect << 'EOF'
#!/bin/bash
for interface in $(ls /sys/class/net); do
    echo 1 > /proc/sys/net/ipv4/conf/$interface/rp_filter
done
EOF
    chmod +x /etc/network/if-pre-up.d/spoofprotect
    print_success "IP spoofing protection configured"
else
    print_info "IP spoofing protection already configured"
fi

# Limit ICMP ping requests
if [[ ! -f /etc/network/if-pre-up.d/limitping ]]; then
    cat > /etc/network/if-pre-up.d/limitping << 'EOF'
#!/bin/bash
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
EOF
    chmod +x /etc/network/if-pre-up.d/limitping
    print_success "ICMP ping limiting configured"
else
    print_info "ICMP ping limiting already configured"
fi

# Enable SYN cookies
echo 1 > /proc/sys/net/ipv4/tcp_syncookies || print_warning "Failed to enable SYN cookies"
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
print_success "SYN cookies enabled"

print_separator
print_success "Firewall Setup Phase 3 completed successfully"
exit 0
