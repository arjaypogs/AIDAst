#!/usr/bin/env bash
# ==============================================================================
# AIDA - LAN / Production Startup Script
# ==============================================================================
# Serves the React build via Nginx on port 31337 (LAN-accessible).
# Automatically tears down the dev stack first to avoid port conflicts.
#
# Usage:
#   ./start-lan.sh           # Auto-detect LAN IP
#   ./start-lan.sh --build   # Force rebuild images
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}\n${BLUE}  $*${NC}\n${BLUE}══════════════════════════════════════${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

FORCE_BUILD=false
for arg in "$@"; do
    case $arg in
        --build|-b) FORCE_BUILD=true ;;
        --help|-h)
            echo "Usage: ./start-lan.sh [--build]"
            echo "  --build, -b    Force rebuild images"
            exit 0
            ;;
    esac
done

# ==============================================================================
# DOCKER COMPOSE COMMAND
# ==============================================================================

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose not found. Install Docker Desktop or docker-compose."
fi

DEV_FILES="-f docker-compose.yml"
PROD_FILES="-f docker-compose.yml -f docker-compose.prod.yml"

AIDA_PORT=31337

section "AIDA - LAN / Production Mode  [:${AIDA_PORT}]"

# ==============================================================================
# TEAR DOWN DEV STACK (releases ports 8000 + 5173 completely)
# ==============================================================================

# Count containers that belong to this compose project (any state)
ALL_CONTAINERS=$($COMPOSE_CMD $DEV_FILES ps -a -q 2>/dev/null | wc -l | tr -d ' ')
RUNNING_CONTAINERS=$($COMPOSE_CMD $DEV_FILES ps --status running -q 2>/dev/null | wc -l | tr -d ' ')

if [[ "$RUNNING_CONTAINERS" -gt 0 ]]; then
    warn "Dev stack is running — tearing it down to release ports..."
    # 'down' removes containers + networks, preserves volumes (data safe)
    $COMPOSE_CMD $DEV_FILES down --timeout 15
    log "Dev stack stopped — data preserved"
elif [[ "$ALL_CONTAINERS" -gt 0 ]]; then
    # Containers exist but are stopped — remove them so prod can recreate cleanly
    $COMPOSE_CMD $DEV_FILES down --timeout 5 2>/dev/null || true
fi

# Give the kernel a moment to fully release port bindings
sleep 1

# ==============================================================================
# VERIFY PORTS ARE FREE
# ==============================================================================

check_port() {
    local port=$1
    local name=$2
    # Docker runtimes (OrbStack, Docker Desktop) forward container ports —
    # they will always appear on our ports. Not a real conflict.
    local docker_runtimes="OrbStack|com.docker|dockerd|Docker"

    local process=""
    if command -v lsof &>/dev/null; then
        process=$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==2 {print $1}')
    elif command -v ss &>/dev/null; then
        process=$(ss -tlnp 2>/dev/null | grep ":$port " | sed 's/.*users:(("\([^"]*\)".*/\1/')
    fi

    if [[ -n "$process" ]] && ! echo "$process" | grep -qE "$docker_runtimes"; then
        warn "Port $port ($name) is in use by: $process"
        warn "Run: lsof -iTCP:$port -sTCP:LISTEN"
        return 1
    fi
    return 0
}

PORT_OK=true
check_port 8000         "Backend API" || PORT_OK=false
check_port $AIDA_PORT   "Frontend"    || PORT_OK=false

if [[ "$PORT_OK" == "false" ]]; then
    echo ""
    read -rp "Ports still blocked. Continue anyway? (y/N): " -n 1 REPLY
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && error "Aborted. Free the ports above and retry."
fi

# ==============================================================================
# DETECT LAN IP
# ==============================================================================

HOST_IP=""

# macOS: try common interfaces in order
if command -v ipconfig &>/dev/null; then
    for iface in en0 en1 en2 en3; do
        candidate=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
        if [[ -n "$candidate" ]]; then
            HOST_IP="$candidate"
            break
        fi
    done
fi

# Linux fallback
if [[ -z "$HOST_IP" ]] && command -v hostname &>/dev/null; then
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
fi

# Manual fallback
if [[ -z "$HOST_IP" ]]; then
    warn "Could not auto-detect LAN IP."
    read -rp "Enter your machine's LAN IP (e.g. 192.168.1.10): " HOST_IP
fi

log "LAN IP : $HOST_IP"

# CORS: allow the LAN address and localhost variants (all on port 31337)
export BACKEND_CORS_ORIGINS="http://${HOST_IP}:${AIDA_PORT},http://localhost:${AIDA_PORT},http://127.0.0.1:${AIDA_PORT}"

# ==============================================================================
# BUILD
# ==============================================================================

section "Building Production Stack"

if [[ "$FORCE_BUILD" == "true" ]]; then
    log "Rebuilding all images..."
    $COMPOSE_CMD $PROD_FILES build
else
    log "Building images (skips if nothing changed)..."
    $COMPOSE_CMD $PROD_FILES build --quiet
fi

# ==============================================================================
# START
# ==============================================================================

section "Starting Containers"

$COMPOSE_CMD $PROD_FILES up -d --remove-orphans

# ==============================================================================
# WAIT FOR SERVICES
# ==============================================================================

section "Waiting for Services"

wait_for() {
    local name=$1
    local cmd=$2
    local max=${3:-60}
    local i=0
    printf "  %-14s " "${name}..."
    while ! eval "$cmd" &>/dev/null; do
        ((i++))
        if [[ $i -ge $max ]]; then
            echo -e "${RED}TIMEOUT${NC}"
            echo ""
            warn "Check logs: $COMPOSE_CMD $PROD_FILES logs"
            return 1
        fi
        sleep 1
    done
    echo -e "${GREEN}Ready${NC}"
}

wait_for "PostgreSQL" "$COMPOSE_CMD $PROD_FILES exec -T postgres pg_isready -U aida"
wait_for "Backend"    "curl -sf http://localhost:8000/health"
wait_for "Frontend"   "curl -sf http://localhost:${AIDA_PORT}" 90

# ==============================================================================
# DONE
# ==============================================================================

section "AIDA Ready"
echo ""
log "Web interface  : http://${HOST_IP}:${AIDA_PORT}"
log "Backend API    : http://localhost:8000/api  (localhost only)"
log "API docs       : http://localhost:8000/docs"
echo ""
echo -e "  ${BLUE}Share with your team →${NC}  http://${HOST_IP}:${AIDA_PORT}"
echo ""
$COMPOSE_CMD $PROD_FILES ps --format "table {{.Name}}\t{{.Status}}"
echo ""
