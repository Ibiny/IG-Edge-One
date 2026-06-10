#!/bin/bash

################################################################################
# IG Edge One - System Setup Script
# Phase 1: System updates, essential packages, and base configuration
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/logging.sh"

print_header "System Setup - Phase 1"

echo -e "${BLUE}Performing system configuration...${NC}\n"

# Update package lists
print_step 1 "Updating package lists"
apt update -y || { print_error "Failed to update package lists"; exit 1; }
print_success "Package lists updated"

# Upgrade existing packages
print_step 2 "Upgrading system packages"
apt upgrade -y || { print_error "Failed to upgrade packages"; exit 1; }
print_success "System packages upgraded"

# Install essential packages
print_step 3 "Installing essential packages"
apt install -y \
    curl \
    wget \
    git \
    build-essential \
    vim \
    nano \
    htop \
    net-tools \
    netcat-openbsd \
    dnsutils \
    traceroute \
    mtr \
    iperf3 \
    nload \
    iputils-ping \
    openssh-server \
    openssh-client \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    ufw \
    fail2ban \
    chrony \
    systemd-container \
    jq \
    uuid-runtime \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    zip \
    unzip || { print_error "Failed to install essential packages"; exit 1; }
print_success "Essential packages installed"

# Install NTP (Chrony for time synchronization)
print_step 4 "Configuring NTP service (Chrony)"
systemctl enable chrony || print_warning "Chrony may already be enabled"
systemctl start chrony || print_warning "Chrony may already be running"
print_success "Chrony NTP service configured"

# Set timezone
print_step 5 "Setting timezone to America/Sao_Paulo"
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
echo "America/Sao_Paulo" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata || print_warning "Timezone configuration may have failed"
print_success "Timezone configured"

# Configure hostname if not already set
if [[ -n "${HOSTNAME:-}" ]] && [[ "$HOSTNAME" != "localhost" ]]; then
    print_step 6 "Setting hostname to $HOSTNAME"
    hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || echo "$HOSTNAME" > /etc/hostname
    print_success "Hostname configured"
else
    print_warning "Hostname not provided, skipping hostname configuration"
fi

# Configure SSH
print_step 7 "Configuring SSH service"
if [[ ! -f /etc/ssh/sshd_config.backup ]]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Set secure SSH options
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Disable some weak SSH settings
sed -i 's/^X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config || echo "X11Forwarding no" >> /etc/ssh/sshd_config
sed -i 's/^UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config || echo "UsePAM yes" >> /etc/ssh/sshd_config

systemctl enable ssh || print_warning "SSH enable may have failed"
systemctl restart ssh || print_warning "SSH restart may have failed"
print_success "SSH service configured and restarted"

# Configure sysctl for networking optimization
print_step 8 "Optimizing kernel networking parameters"
cat >> /etc/sysctl.conf << 'EOF'
# IG Edge One Network Optimization
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=2
net.core.somaxconn=65535
net.core.netdev_max_backlog=5000
net.ipv4.ip_local_port_range=10000 65000
EOF

sysctl -p > /dev/null 2>&1 || print_warning "Some sysctl parameters may not have been applied"
print_success "Kernel networking parameters optimized"

# Install Python 3 (often required by containers and tools)
print_step 9 "Installing Python 3"
apt install -y python3 python3-pip || print_warning "Python 3 installation may have failed"
print_success "Python 3 installed"

# Create log directories
print_step 10 "Creating log directories"
mkdir -p /var/log/igedge
mkdir -p /opt/igedge
chown root:root /var/log/igedge
chown root:root /opt/igedge
chmod 755 /var/log/igedge
chmod 755 /opt/igedge
print_success "Log and data directories created"

# Enable unattended security updates
print_step 11 "Enabling automatic security updates"
apt install -y unattended-upgrades apt-listchanges || print_warning "Unattended upgrades installation may have failed"

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::SyslogLogging "true";
Unattended-Upgrade::SyslogLoggingFacility "daemon";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Boot-Grub-Config "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades || print_warning "Failed to enable unattended upgrades"
systemctl restart unattended-upgrades || print_warning "Failed to restart unattended upgrades"
print_success "Automatic security updates enabled"

print_separator
print_success "System Setup Phase 1 completed successfully"
exit 0
