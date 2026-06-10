#!/bin/bash

################################################################################
# IG Edge One - Docker Setup Script
# Installs Docker Engine and Docker Compose
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../helpers/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../helpers/logging.sh"

print_header "Docker Setup - Phase 2"

print_info "Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

print_info "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

print_info "Updating package lists..."
apt update -y

print_info "Installing Docker Engine..."
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

print_info "Creating igedge Docker network..."
docker network create igedge-network || print_warning "Network already exists"

print_info "Enabling Docker service..."
systemctl enable docker
systemctl start docker

print_info "Configuring Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}
EOF

systemctl restart docker

print_info "Installing docker-compose..."
apt install -y docker-compose-plugin

print_success "Docker setup completed successfully"
exit 0