#!/bin/bash

################################################################################
# IG Edge One - System Update Script
# Updates system packages, Docker images, and containers
#
# Usage: sudo ./scripts/update.sh [--full|--security-only]
################################################################################

set -euo pipefail

# Colors and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_DIR="/var/log/igedge"
LOG_FILE="$LOG_DIR/update.log"
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../backup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/../docker"

# Configuration
UPDATE_TYPE="${1:-full}"
FULL_BACKUP=false
RESTART_CONTAINERS=true
PRUNE_UNUSED=true
SCHEDULE_REBOOT=false

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    log ">>> $1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "[SUCCESS] $1"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
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
        print_error "This script must be run as root (use: sudo ./scripts/update.sh)"
        exit 1
    fi
}

check_internet() {
    print_info "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connectivity detected"
        exit 1
    fi
    print_success "Internet connectivity confirmed"
}

backup_configuration() {
    local backup_file="$BACKUP_DIR/igedge-pre-update-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
    
    print_info "Creating pre-update backup..."
    mkdir -p "$BACKUP_DIR"
    
    tar -czf "$backup_file" \
        --exclude="$BACKUP_DIR" \
        /etc/unbound \
        /opt/igedge \
        /etc/fail2ban \
        /etc/docker \
        2>/dev/null || print_warning "Some directories may not exist"
    
    print_success "Backup created: $backup_file"
}

update_system_packages() {
    print_header "Phase 1: Updating System Packages"
    
    print_info "Updating package lists..."
    apt update -y || { print_error "Failed to update package lists"; return 1; }
    print_success "Package lists updated"
    
    if [[ "$UPDATE_TYPE" == "security-only" ]]; then
        print_info "Installing security updates only..."
        apt install -y --only-upgrade $(apt list --upgradable 2>/dev/null | grep -i security | cut -d '/' -f 1) || print_warning "No security-only updates available"
    else
        print_info "Upgrading all packages..."
        apt upgrade -y || print_warning "Some packages may have failed to upgrade"
        
        print_info "Performing distribution upgrade..."
        apt dist-upgrade -y || print_warning "Distribution upgrade may have encountered issues"
    fi
    
    print_info "Cleaning up unused packages..."
    apt autoremove -y || print_warning "Autoremove encountered issues"
    apt autoclean -y || print_warning "Autoclean encountered issues"
    
    print_success "System packages updated"
}

update_docker_images() {
    print_header "Phase 2: Updating Docker Images & Containers"
    
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not found, skipping container updates"
        return 0
    fi
    
    print_info "Checking Docker service..."
    if ! systemctl is-active --quiet docker; then
        print_error "Docker service is not running"
        return 1
    fi
    print_success "Docker service is running"
    
    cd "$DOCKER_DIR" || { print_error "Docker directory not found"; return 1; }
    
    # Pull latest images
    print_info "Pulling latest Docker images..."
    docker compose pull --quiet || { print_error "Failed to pull Docker images"; return 1; }
    print_success "Docker images pulled"
    
    # Restart containers with new images
    if [[ "$RESTART_CONTAINERS" == "true" ]]; then
        print_info "Restarting Docker containers with updated images..."
        docker compose up -d --remove-orphans || { print_error "Failed to restart containers"; return 1; }
        print_success "Docker containers restarted"
        
        # Wait for containers to be ready
        print_info "Waiting for containers to stabilize..."
        sleep 10
    fi
    
    # Prune unused Docker resources
    if [[ "$PRUNE_UNUSED" == "true" ]]; then
        print_info "Cleaning up unused Docker resources..."
        docker image prune -af --filter "until=240h" || print_warning "Docker prune encountered issues"
        docker container prune -f || print_warning "Docker container prune encountered issues"
        print_success "Docker cleanup completed"
    fi
}

check_service_health() {
    print_header "Phase 3: Service Health Check"
    
    print_info "Verifying services..."
    
    local failed_count=0
    
    # Check Docker
    if systemctl is-active --quiet docker; then
        print_success "Docker service is running"
    else
        print_error "Docker service is NOT running"
        failed_count=$((failed_count + 1))
    fi
    
    # Check UFW
    if systemctl is-active --quiet ufw; then
        print_success "UFW firewall is active"
    else
        print_warning "UFW firewall is not active"
    fi
    
    # Check Fail2Ban
    if systemctl is-active --quiet fail2ban; then
        print_success "Fail2Ban is running"
    else
        print_warning "Fail2Ban is not running"
    fi
    
    # Check Chrony
    if systemctl is-active --quiet chrony; then
        print_success "Chrony NTP service is running"
    else
        print_warning "Chrony NTP service is not running"
    fi
    
    # Check Docker containers
    if cd "$DOCKER_DIR" 2>/dev/null && docker compose ps -q | grep -q .; then
        print_success "Docker containers are running"
        echo ""
        docker compose ps
        echo ""
    else
        print_warning "No Docker containers found"
        failed_count=$((failed_count + 1))
    fi
    
    return $failed_count
}

show_update_report() {
    print_header "Update Report"
    
    cat << EOF

${GREEN}Update completed at: $(date)${NC}

Update Type: $UPDATE_TYPE
Backup Location: $BACKUP_DIR
Log File: $LOG_FILE

${BLUE}Recommended Next Steps:${NC}
  1. Review the update log: tail -f $LOG_FILE
  2. Monitor container logs: docker compose -f $DOCKER_DIR/docker-compose.yml logs -f
  3. Test service functionality
  4. Check system status: systemctl status

${YELLOW}Note:${NC}
  - Backup created before update for rollback capability
  - Docker containers automatically restarted with new images
  - Unused Docker resources cleaned up
  - System packages upgraded to latest versions

EOF
}

show_help() {
    cat << EOF
Usage: sudo ./scripts/update.sh [options]

Options:
  full              Update all system packages and Docker images (default)
  --security-only   Install security updates only
  --help            Show this help message

Examples:
  sudo ./scripts/update.sh
  sudo ./scripts/update.sh --security-only
  sudo ./scripts/update.sh full

EOF
}

# Main execution
main() {
    print_header "IG Edge One - System Update"
    
    # Validate options
    case "$UPDATE_TYPE" in
        --help|help)
            show_help
            exit 0
            ;;
        full|--full)
            UPDATE_TYPE="full"
            print_info "Update type: Full system and container update"
            ;;
        --security-only|security-only)
            UPDATE_TYPE="security-only"
            print_info "Update type: Security updates only"
            ;;
        *)
            print_error "Invalid update type: $UPDATE_TYPE"
            show_help
            exit 1
            ;;
    esac
    
    # Pre-flight checks
    check_root
    check_internet
    
    # Backup before update
    backup_configuration
    
    # Update system
    if ! update_system_packages; then
        print_error "System package update failed"
        exit 1
    fi
    
    # Update Docker
    if ! update_docker_images; then
        print_error "Docker update failed"
        exit 1
    fi
    
    # Health check
    check_service_health
    
    # Show report
    show_update_report
    
    print_success "Update process completed successfully"
    log "Update process completed"
}

# Run main function
main "$@"
