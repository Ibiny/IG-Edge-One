#!/bin/bash

################################################################################
# IG Edge One - Health Check Script
# Verifies all services are running correctly
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../helpers/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../helpers/logging.sh"

print_header "Service Health Check - Phase 6"

DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/docker"
FAILED=0

# Check Docker
print_info "Checking Docker service..."
if systemctl is-active --quiet docker; then
    print_success "Docker service is running"
else
    print_error "Docker service is NOT running"
    FAILED=$((FAILED + 1))
fi

# Check Docker containers
print_info "Checking Docker containers..."
cd "$DOCKER_DIR"

if docker compose ps -q | grep -q .; then
    print_success "Docker containers are running:"
    docker compose ps
else
    print_error "No Docker containers running"
    FAILED=$((FAILED + 1))
fi

# Check UFW
print_info "Checking firewall (UFW)..."
if systemctl is-active --quiet ufw; then
    print_success "UFW firewall is enabled"
else
    print_error "UFW firewall is NOT enabled"
    FAILED=$((FAILED + 1))
fi

# Check Fail2Ban
print_info "Checking Fail2Ban..."
if systemctl is-active --quiet fail2ban; then
    print_success "Fail2Ban is running"
else
    print_error "Fail2Ban is NOT running"
    FAILED=$((FAILED + 1))
fi

# Check Chrony
print_info "Checking NTP synchronization (Chrony)..."
if systemctl is-active --quiet chrony; then
    print_success "Chrony is running"
else
    print_error "Chrony is NOT running"
    FAILED=$((FAILED + 1))
fi

# Check services accessibility
print_info "Checking service ports..."

services=(
    "LibreSpeed:80:tcp"
    "DNS:53:udp"
    "Uptime Kuma:3001:tcp"
    "WireGuard:51820:udp"
    "Portainer:9443:tcp"
)

for service in "${services[@]}"; do
    IFS=: read -r name port proto <<< "$service"
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        print_success "$name is listening on port $port/$proto"
    else
        print_warning "$name may not be ready yet (port $port/$proto)"
    fi
done

print_separator

if [ $FAILED -eq 0 ]; then
    print_success "All health checks passed!"
    exit 0
else
    print_error "$FAILED service(s) failed health check"
    exit 1
fi