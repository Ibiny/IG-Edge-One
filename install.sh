#!/bin/bash

################################################################################
# IG Edge One - Automated ISP Appliance Installation
# 
# Installation Script for Debian 13
# Single-command deployment with security hardening
#
# Usage: sudo ./install.sh
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_DIR="/var/log/igedge"
LOG_FILE="$LOG_DIR/install.log"
START_TIME=$(date +%s)

# Installation paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPTS_DIR="$SCRIPT_DIR/scripts/setup"
HELPER_DIR="$SCRIPT_DIR/scripts/helpers"
DOCKER_DIR="$SCRIPT_DIR/docker"
CONFIG_DIR="$SCRIPT_DIR/config"
UNBOUND_DIR="$SCRIPT_DIR/unbound"
FAIL2BAN_DIR="$SCRIPT_DIR/fail2ban"
BACKUP_DIR="$SCRIPT_DIR/backup"

# State
INSTALLATION_STATE="starting"
FAILED_SERVICES=()
SUCCESSFUL_SERVICES=()

################################################################################
# UTILITY FUNCTIONS
################################################################################

setup_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
    log ">>> $1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "[SUCCESS] $1"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    log "[ERROR] $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log "[WARNING] $1"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
    log "[INFO] $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use: sudo ./install.sh)"
        exit 1
    fi
    print_success "Running with root privileges"
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "debian" ]] || [[ "${VERSION_ID}" != "13" ]]; then
        print_warning "This script is optimized for Debian 13. Current OS: $ID $VERSION_ID"
        print_warning "Proceeding with caution..."
    fi
    
    print_success "OS Check: $ID $VERSION_ID"
}

check_internet() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connectivity detected"
        exit 1
    fi
    print_success "Internet connectivity confirmed"
}

check_disk_space() {
    available=$(df / | awk 'NR==2 {print $4}')
    required=$((10 * 1024 * 1024))  # 10GB
    
    if [[ $available -lt $required ]]; then
        print_error "Insufficient disk space (required 10GB, available: $(($available / 1024 / 1024))GB)"
        exit 1
    fi
    print_success "Disk space check passed"
}

################################################################################
# USER INPUT FUNCTIONS
################################################################################

get_ipv4() {
    print_info "Detecting IPv4 address..."
    
    # Try to detect automatically
    local detected_ipv4=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${BLUE}Enter your public IPv4 address:${NC}"
    if [[ -n "$detected_ipv4" ]]; then
        echo "Detected IP: $detected_ipv4"
        read -p "Use detected IP? (y/n) [y]: " -r use_detected
        use_detected=${use_detected:-y}
        
        if [[ "$use_detected" == "y" ]]; then
            IPV4_ADDRESS="$detected_ipv4"
        else
            read -p "Enter IPv4 address: " IPV4_ADDRESS
        fi
    else
        read -p "Enter your public IPv4 address: " IPV4_ADDRESS
    fi
    
    if [[ ! "$IPV4_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IPv4 address format"
        get_ipv4
    fi
    
    print_success "IPv4 Address: $IPV4_ADDRESS"
}

get_ipv6() {
    print_info "Detecting IPv6 address..."
    
    # Try to detect automatically
    IPV6_ADDRESS=$(hostname -I | grep -oP '(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}' || echo "")
    
    if [[ -n "$IPV6_ADDRESS" ]]; then
        print_success "IPv6 Address: $IPV6_ADDRESS"
    else
        print_warning "No IPv6 address detected (IPv6 may not be configured on your network)"
        IPV6_ADDRESS=""
    fi
}

get_hostname() {
    echo -e "\n${BLUE}Enter appliance hostname:${NC}"
    local current_hostname=$(hostname)
    read -p "Hostname [igedge-one]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-igedge-one}
    
    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid hostname format"
        get_hostname
    fi
    
    print_success "Hostname: $HOSTNAME"
}

get_wg_password() {
    echo -e "\n${BLUE}Set WireGuard admin password:${NC}"
    read -sp "WireGuard admin password: " WG_ADMIN_PASSWORD
    echo ""
    
    read -sp "Confirm password: " WG_ADMIN_PASSWORD_CONFIRM
    echo ""
    
    if [[ "$WG_ADMIN_PASSWORD" != "$WG_ADMIN_PASSWORD_CONFIRM" ]]; then
        print_error "Passwords do not match"
        get_wg_password
    fi
    
    if [[ ${#WG_ADMIN_PASSWORD} -lt 8 ]]; then
        print_error "Password must be at least 8 characters"
        get_wg_password
    fi
    
    print_success "WireGuard password configured"
}

generate_portainer_password() {
    PORTAINER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    print_success "Portainer password generated"
}

show_configuration_summary() {
    print_header "Installation Configuration Summary"
    
    cat << EOF

${BLUE}Network Configuration:${NC}
  IPv4 Address:        $IPV4_ADDRESS
  IPv6 Address:        ${IPV6_ADDRESS:-"Not detected"}
  Hostname:            $HOSTNAME
  Domain:              $HOSTNAME.local

${BLUE}Security Configuration:${NC}
  SSH Port:            22/TCP
  Fail2Ban:            Enabled (24h bans)
  UFW Firewall:        Enabled
  DNSSEC:              Enabled

${BLUE}Services to Deploy:${NC}
  • LibreSpeed (Port 80)
  • Unbound DNS (Port 53)
  • Uptime Kuma (Port 3001)
  • WireGuard Easy (Port 51820/UDP, 51821/TCP)
  • Portainer (Port 9443)

${BLUE}Storage Configuration:${NC}
  Docker Network:      igedge-network
  Data Volume:         /opt/igedge
  Backup Directory:    $BACKUP_DIR
  Backup Retention:    30 days

${BLUE}System Configuration:${NC}
  Timezone:            America/Sao_Paulo
  NTP Service:         Chrony
  Log Retention:       30 days
  Docker Restart:      unless-stopped

EOF
    
    echo -ne "${YELLOW}Do you want to proceed with this configuration? (yes/no): ${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_error "Installation cancelled by user"
        exit 0
    fi
}

################################################################################
# INSTALLATION PHASES
################################################################################

phase_1_system_setup() {
    print_header "PHASE 1: System Setup & Package Installation"
    
    if [[ ! -f "$SETUP_SCRIPTS_DIR/system-setup.sh" ]]; then
        print_error "System setup script not found at $SETUP_SCRIPTS_DIR/system-setup.sh"
        return 1
    fi
    
    bash "$SETUP_SCRIPTS_DIR/system-setup.sh"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "Phase 1 completed: System setup"
        return 0
    else
        print_error "Phase 1 failed: System setup"
        return 1
    fi
}

phase_2_docker_setup() {
    print_header "PHASE 2: Docker Engine Installation & Configuration"
    
    if [[ ! -f "$SETUP_SCRIPTS_DIR/docker-setup.sh" ]]; then
        print_error "Docker setup script not found"
        return 1
    fi
    
    bash "$SETUP_SCRIPTS_DIR/docker-setup.sh"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "Phase 2 completed: Docker setup"
        return 0
    else
        print_error "Phase 2 failed: Docker setup"
        return 1
    fi
}

phase_3_firewall_setup() {
    print_header "PHASE 3: Firewall Configuration (UFW)"
    
    if [[ ! -f "$SETUP_SCRIPTS_DIR/firewall-setup.sh" ]]; then
        print_error "Firewall setup script not found"
        return 1
    fi
    
    bash "$SETUP_SCRIPTS_DIR/firewall-setup.sh"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "Phase 3 completed: Firewall setup"
        return 0
    else
        print_error "Phase 3 failed: Firewall setup"
        return 1
    fi
}

phase_4_fail2ban_setup() {
    print_header "PHASE 4: Fail2Ban Installation & Configuration"
    
    if [[ ! -f "$SETUP_SCRIPTS_DIR/fail2ban-setup.sh" ]]; then
        print_error "Fail2Ban setup script not found"
        return 1
    fi
    
    bash "$SETUP_SCRIPTS_DIR/fail2ban-setup.sh"
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        print_success "Phase 4 completed: Fail2Ban setup"
        return 0
    else
        print_error "Phase 4 failed: Fail2Ban setup"
        return 1
    fi
}

phase_5_services_deployment() {
    print_header "PHASE 5: Services Deployment"
    
    # Create necessary directories
    mkdir -p "$BACKUP_DIR"
    mkdir -p /opt/igedge/{unbound,uptime-kuma,wg-easy,portainer}
    
    print_info "Creating environment configuration..."
    create_env_file
    
    print_info "Starting Docker services..."
    cd "$DOCKER_DIR"
    
    docker compose up -d
    if [[ $? -ne 0 ]]; then
        print_error "Failed to start Docker services"
        return 1
    fi
    
    print_success "Docker services started"
    
    # Wait for services to be ready
    print_info "Waiting for services to become ready..."
    sleep 15
    
    return 0
}

phase_6_health_check() {
    print_header "PHASE 6: Service Health Verification"
    
    if [[ ! -f "$SETUP_SCRIPTS_DIR/health-check.sh" ]]; then
        print_error "Health check script not found"
        return 1
    fi
    
    bash "$SETUP_SCRIPTS_DIR/health-check.sh"
    local result=$?
    
    return $result
}

create_env_file() {
    cat > "$DOCKER_DIR/.env" << EOF
# IG Edge One Environment Configuration
# Generated: $(date)

# Network Configuration
IPV4_ADDRESS=$IPV4_ADDRESS
IPV6_ADDRESS=$IPV6_ADDRESS
HOSTNAME=$HOSTNAME
TIMEZONE=America/Sao_Paulo

# Security
PORTAINER_PASSWORD=$PORTAINER_PASSWORD
WG_ADMIN_PASSWORD=$WG_ADMIN_PASSWORD

# Docker Configuration
DOCKER_NETWORK=igedge-network
DATA_VOLUME=/opt/igedge

# DNS Configuration
DNS_CACHE_SIZE=64m
DNS_RRSET_CACHE=128m

# Services
LIBRESPEED_PORT=80
UPTIME_KUMA_PORT=3001
WIREGUARD_UDP_PORT=51820
WIREGUARD_TCP_PORT=51821
PORTAINER_PORT=9443

# Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE="0 2 * * *"
EOF
    
    print_success "Environment file created: $DOCKER_DIR/.env"
}

################################################################################
# INSTALLATION COMPLETION
################################################################################

show_installation_report() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    print_header "Installation Report"
    
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}IG EDGE ONE - INSTALLATION COMPLETED SUCCESSFULLY${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}Installation Summary:${NC}
  Duration:             $(printf '%dh %dm %ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
  Start Time:           $(date -d @$START_TIME)
  End Time:             $(date)
  System:               $(lsb_release -ds)

${BLUE}Network Information:${NC}
  IPv4 Address:         $IPV4_ADDRESS
  IPv6 Address:         ${IPV6_ADDRESS:-"Not configured"}
  Hostname:             $HOSTNAME
  DNS Server:           127.0.0.1 (Unbound)

${BLUE}Service Access URLs:${NC}
  Portainer UI:         https://$IPV4_ADDRESS:9443
  Uptime Kuma:          http://$IPV4_ADDRESS:3001
  LibreSpeed:           http://$IPV4_ADDRESS
  WireGuard Manager:    http://$IPV4_ADDRESS:51821
  SSH Access:           ssh root@$IPV4_ADDRESS (port 22)

${BLUE}Default Credentials:${NC}
  Portainer Username:   admin
  Portainer Password:   $PORTAINER_PASSWORD
  WireGuard Password:   [As configured during installation]
  SSH:                  root (password authentication enabled)

${BLUE}Important Directories:${NC}
  Installation:         $SCRIPT_DIR
  Docker Compose:       $DOCKER_DIR
  Configuration:        $CONFIG_DIR
  Backups:              $BACKUP_DIR
  Logs:                 $LOG_FILE

${BLUE}Maintenance Commands:${NC}
  Update System:        sudo $SCRIPT_DIR/scripts/update.sh
  Backup Data:          sudo $SCRIPT_DIR/scripts/backup.sh
  View Logs:            tail -f $LOG_FILE
  Service Status:       docker compose -f $DOCKER_DIR/docker-compose.yml ps

${BLUE}Next Steps:${NC}
  1. Change SSH to key-based authentication (recommended)
  2. Configure DNS access lists in Unbound
  3. Set up monitoring dashboards in Portainer
  4. Review logs at: $LOG_FILE

${YELLOW}SECURITY NOTES:${NC}
  • Default SSH password authentication is ENABLED
  • Consider disabling password auth after key setup
  • Ensure regular backups with: $SCRIPT_DIR/scripts/backup.sh
  • Monitor system health in Portainer dashboard
  • Update regularly with: $SCRIPT_DIR/scripts/update.sh

${BLUE}Support & Documentation:${NC}
  Documentation:        README.md
  Architecture:         docs/ARCHITECTURE.md
  Security Details:     docs/SECURITY.md
  Troubleshooting:      docs/TROUBLESHOOTING.md

${GREEN}═══════════════════════════════════════════════════════════════${NC}

${GREEN}IG Edge One is now operational!${NC}

Log file saved: $LOG_FILE

EOF
}

show_error_report() {
    print_header "Installation Error Report"
    
    echo -e "${RED}Installation failed at: PHASE $CURRENT_PHASE${NC}\n"
    
    if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
        echo -e "${RED}Failed Services:${NC}"
        for service in "${FAILED_SERVICES[@]}"; do
            echo -e "  ${RED}✗ $service${NC}"
        done
        echo ""
    fi
    
    if [[ ${#SUCCESSFUL_SERVICES[@]} -gt 0 ]]; then
        echo -e "${GREEN}Completed Services:${NC}"
        for service in "${SUCCESSFUL_SERVICES[@]}"; do
            echo -e "  ${GREEN}✓ $service${NC}"
        done
        echo ""
    fi
    
    echo -e "${YELLOW}For detailed troubleshooting:${NC}"
    echo "  • View installation log: tail -f $LOG_FILE"
    echo "  • Check Docker logs: docker compose -f $DOCKER_DIR/docker-compose.yml logs"
    echo "  • Review firewall: sudo ufw status verbose"
    echo "  • See: docs/TROUBLESHOOTING.md"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    clear
    
    # Setup logging
    setup_logging
    
    print_header "IG EDGE ONE - Installation Wizard"
    
    echo -e "${BLUE}Performing pre-installation checks...${NC}\n"
    
    # Pre-flight checks
    check_root
    check_os
    check_internet
    check_disk_space
    
    # Collect user input
    get_ipv4
    get_ipv6
    get_hostname
    get_wg_password
    generate_portainer_password
    
    # Show configuration summary
    show_configuration_summary
    
    # Execution phases
    CURRENT_PHASE=1
    phase_1_system_setup || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("System Setup")
    
    CURRENT_PHASE=2
    phase_2_docker_setup || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("Docker Engine")
    
    CURRENT_PHASE=3
    phase_3_firewall_setup || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("UFW Firewall")
    
    CURRENT_PHASE=4
    phase_4_fail2ban_setup || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("Fail2Ban")
    
    CURRENT_PHASE=5
    phase_5_services_deployment || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("All Services")
    
    CURRENT_PHASE=6
    phase_6_health_check || { show_error_report; exit 1; }
    SUCCESSFUL_SERVICES+=("Health Check")
    
    # Show completion report
    show_installation_report
}

# Run main installation
main "$@"