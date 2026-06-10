#!/bin/bash

################################################################################
# IG Edge One - Logging Helper Functions
# Provides consistent logging and output formatting
################################################################################

# Source colors if available
if [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi

LOG_DIR="${LOG_DIR:-/var/log/igedge}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/system.log}"

# Ensure log directory exists
mkdir -p "$LOG_DIR" 2>/dev/null || true

print_separator() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    [[ -n "${LOG_FILE}" ]] && echo "════════════════════════════════════════════════════════════════" >> "$LOG_FILE"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD_BLUE}$title${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ -n "${LOG_FILE}" ]]; then
        echo "" >> "$LOG_FILE"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ========== $title =========" >> "$LOG_FILE"
    fi
}

print_success() {
    local message="$1"
    echo -e "${GREEN}✓ $message${NC}"
    [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >> "$LOG_FILE"
}

print_error() {
    local message="$1"
    echo -e "${RED}✗ $message${NC}" >&2
    [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠ $message${NC}"
    [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $message" >> "$LOG_FILE"
}

print_info() {
    local message="$1"
    echo -e "${BLUE}ℹ $message${NC}"
    [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $message" >> "$LOG_FILE"
}

print_debug() {
    local message="$1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}🔍 $message${NC}"
        [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $message" >> "$LOG_FILE"
    fi
}

print_step() {
    local step_num="$1"
    local message="$2"
    echo -e "${BLUE}[Step $step_num]${NC} ${BOLD_BLUE}$message${NC}"
    [[ -n "${LOG_FILE}" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [STEP $step_num] $message" >> "$LOG_FILE"
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if command -v "$cmd" &> /dev/null; then
        print_success "$name found"
        return 0
    else
        print_error "$name not found"
        return 1
    fi
}

require_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if ! command -v "$cmd" &> /dev/null; then
        print_error "Required command not found: $name"
        exit 1
    fi
}
