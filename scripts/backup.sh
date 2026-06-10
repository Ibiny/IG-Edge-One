#!/bin/bash

################################################################################
# IG Edge One - Backup Script
# Backs up configurations and data with retention policy
#
# Usage: sudo ./scripts/backup.sh
################################################################################

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers/logging.sh"

print_header "IG Edge One - System Backup"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backup"
RETENTION_DAYS=30
BACKUP_DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/igedge-backup-$BACKUP_DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

print_info "Creating backup directories..."
BACKUP_DIRS=(
    "/etc/unbound"
    "/opt/igedge"
    "/etc/fail2ban"
    "/etc/docker"
)

print_info "Starting backup process..."
print_info "Backup file: $BACKUP_FILE"

# Create backup
tar -czf "$BACKUP_FILE" \
    --exclude="$BACKUP_DIR" \
    "${BACKUP_DIRS[@]}" 2>/dev/null || print_warning "Some directories may not exist"

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

print_success "Backup created: $BACKUP_SIZE"

print_info "Cleaning old backups (retention: $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "igedge-backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

print_info "Listing recent backups:"
ls -lh "$BACKUP_DIR"/igedge-backup-*.tar.gz | tail -5

print_separator

cat << EOF

${GREEN}Backup Completed Successfully${NC}

Backup Details:
  File: $BACKUP_FILE
  Size: $BACKUP_SIZE
  Date: $(date)

Included:
  • /etc/unbound (DNS config)
  • /opt/igedge (Application data)
  • /etc/fail2ban (Security config)
  • /etc/docker (Docker config)

Retention Policy:
  Backups older than $RETENTION_DAYS days are automatically deleted

To Restore:
  sudo tar -xzf $BACKUP_FILE -C /

EOF

print_success "Backup completed successfully"
exit 0