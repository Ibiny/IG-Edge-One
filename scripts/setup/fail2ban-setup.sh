#!/bin/bash

################################################################################
# IG Edge One - Fail2Ban Setup Script
# Phase 4: Install and configure Fail2Ban for intrusion prevention
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/logging.sh"

print_header "Fail2Ban Setup - Phase 4"

echo -e "${BLUE}Installing and configuring Fail2Ban...${NC}\n"

# Install Fail2Ban
print_step 1 "Installing Fail2Ban package"
apt install -y fail2ban fail2ban-systemd || { print_error "Failed to install Fail2Ban"; exit 1; }
print_success "Fail2Ban installed"

# Copy default configuration as base
print_step 2 "Setting up Fail2Ban configuration"
if [[ ! -f /etc/fail2ban/jail.local ]]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    print_success "Fail2Ban configuration file created"
else
    print_info "Fail2Ban configuration file already exists"
fi

# Configure jail.local
print_step 3 "Configuring Fail2Ban jail settings"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban time: 24 hours (86400 seconds)
bantime = 86400

# Find time: 10 minutes
findtime = 600

# Max retries: 5 attempts
maxretry = 5

# Destemail: root
destemail = root@localhost

# Sender email
sender = root@localhost

# Action: Ban and send email
action = %(action_mwl)s

# Enable SSH jail
[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
maxretry = 5
bantime = 86400
findtime = 600

# Enable recidive jail (repeat offenders get longer bans)
[recidive]
enabled = true
filter = recidive
action = %(action_mwl)s
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 5

# SSH DDoS protection
[sshd-ddos]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 10
findtime = 60
bantime = 3600

# UFW jail
[ufw-sshd]
enabled = false
port = ssh
logpath = /var/log/auth.log
maxretry = 5
bantime = 86400
EOF
print_success "Jail configuration updated"

# Create Fail2Ban filter for SSH
print_step 4 "Creating SSH filter configuration"
cat > /etc/fail2ban/filter.d/sshd-igedge.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* \[.*\] Failed password for (invalid user )?.*port \d+ ssh2?$
            ^<HOST> .* \[.*\] Invalid user .* port \d+ ssh2?$
            ^<HOST> .* \[.*\] Connection closed by <HOST> \[preauth\]$
            ^<HOST> .* \[.*\] Received disconnect from <HOST>.*\[preauth\]$
ignoreregex =
EOF
print_success "SSH filter created"

# Enable and start Fail2Ban
print_step 5 "Enabling Fail2Ban service"
systemctl enable fail2ban || { print_error "Failed to enable Fail2Ban"; exit 1; }
print_success "Fail2Ban enabled to start on boot"

print_step 6 "Starting Fail2Ban service"
systemctl start fail2ban || { print_error "Failed to start Fail2Ban"; exit 1; }
print_success "Fail2Ban service started"

# Verify Fail2Ban is running
print_step 7 "Verifying Fail2Ban status"
if systemctl is-active --quiet fail2ban; then
    print_success "Fail2Ban is running and active"
else
    print_error "Fail2Ban is not running"
    exit 1
fi

# Display jail status
print_step 8 "Checking active jails"
echo ""
echo -e "${CYAN}Fail2Ban Jails Status:${NC}"
fail2ban-client status || print_warning "fail2ban-client may not be available"
echo ""

# Configure logrotate for Fail2Ban logs
print_step 9 "Configuring log rotation"
cat > /etc/logrotate.d/fail2ban << 'EOF'
/var/log/fail2ban.log {
    daily
    rotate 30
    missingok
    compress
    delaycompress
    notifempty
    create 0600 root root
    postrotate
        /usr/lib/fail2ban/fail2ban-before-logrotate
        systemctl reload fail2ban > /dev/null 2>&1 || true
        /usr/lib/fail2ban/fail2ban-after-logrotate
    endscript
}
EOF
print_success "Log rotation configured"

# Create monitoring script
print_step 10 "Creating Fail2Ban monitoring script"
mkdir -p /usr/local/bin
cat > /usr/local/bin/check-fail2ban.sh << 'EOF'
#!/bin/bash
echo "Fail2Ban Status Report - $(date)"
echo "================================="
echo ""
echo "Service Status:"
systemctl status fail2ban --no-pager | grep -E 'Active|inactive'
echo ""
echo "Active Jails:"
fail2ban-client status | grep -E 'Jail list|SSH'
echo ""
echo "SSH Jail Details:"
fail2ban-client status sshd 2>/dev/null || echo "SSHD Jail not active"
echo ""
echo "Recent Bans:"
tail -20 /var/log/fail2ban.log | grep -i ban || echo "No recent bans"
EOF
chmod +x /usr/local/bin/check-fail2ban.sh
print_success "Monitoring script created"

print_separator
print_success "Fail2Ban Setup Phase 4 completed successfully"
print_info "To check status: fail2ban-client status"
print_info "To check SSH jail: fail2ban-client status sshd"
print_info "To unban an IP: fail2ban-client set sshd unbanip <IP>"
exit 0
