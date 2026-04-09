#!/usr/bin/env bash
# ==============================================================================
# AIDA - Stop Services
# ==============================================================================
# Stops all AIDA containers. Data is preserved.
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}\n${BLUE}  $*${NC}\n${BLUE}══════════════════════════════════════${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Docker Compose: prefer plugin, fallback to standalone (Kali)
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

section "AIDA - Stopping Services"

# Stop host helper
if pkill -f "tools/helper.py" 2>/dev/null; then
    log "Stopped Host Helper"
fi
pkill -f "folder_opener.py" 2>/dev/null || true  # legacy name

# Check current state
RUNNING=$($COMPOSE_CMD ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
STOPPED=$($COMPOSE_CMD ps --status exited -q 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((RUNNING + STOPPED))

if [[ "$TOTAL" -eq 0 ]]; then
    warn "No AIDA containers found"
    echo ""
    echo "To start AIDA: ./start.sh"
    exit 0
fi

if [[ "$RUNNING" -eq 0 ]]; then
    warn "Containers already stopped"
    $COMPOSE_CMD ps --format "table {{.Name}}\t{{.Status}}"
    exit 0
fi

# Detect active mode: if port 31337 is mapped, prod stack is running
if $COMPOSE_CMD -f docker-compose.yml -f docker-compose.prod.yml ps --format "{{.Ports}}" 2>/dev/null | grep -q "31337"; then
    log "Prod/LAN stack detected — stopping with prod compose files..."
    STOP_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
else
    STOP_FILES=""
fi

log "Stopping $RUNNING container(s)..."
# Use 'stop' (not 'down') — containers are kept, volumes untouched, data safe
$COMPOSE_CMD $STOP_FILES stop

# Verify
echo ""
log "All containers stopped — data preserved"
$COMPOSE_CMD $STOP_FILES ps --format "table {{.Name}}\t{{.Status}}"
echo ""
log "To restart dev:  ./start.sh"
log "To restart LAN:  ./start-lan.sh"
echo ""
