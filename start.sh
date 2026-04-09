#!/usr/bin/env bash
# ==============================================================================
# AIDA - Docker Startup Script
# ==============================================================================
# Starts the AIDA platform. Smart detection: skips build if already done.
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

# Parse arguments
FORCE_BUILD=false
SKIP_CHECKS=false
for arg in "$@"; do
    case $arg in
        --build|-b)   FORCE_BUILD=true ;;
        --fast|-f)    SKIP_CHECKS=true ;;
        --help|-h)
            echo "Usage: ./start.sh [OPTIONS]"
            echo "  --build, -b    Force rebuild Docker images"
            echo "  --fast, -f     Skip dependency checks (faster startup)"
            echo "  --help, -h     Show this help"
            exit 0
            ;;
    esac
done

section "AIDA - Starting Platform"

# ==============================================================================
# QUICK CHECKS
# ==============================================================================

# Docker check
if ! command -v docker &> /dev/null; then
    error "Docker not installed. Get it from: https://docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    error "Docker daemon not running. Start Docker Desktop first."
    exit 1
fi

# Docker Compose: prefer plugin, fallback to standalone (Kali)
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose not found. Install: sudo apt install docker-compose"
    exit 1
fi

# ==============================================================================
# CHECK PORT CONFLICTS
# ==============================================================================

check_port() {
    local port=$1
    local service=$2
    # Docker runtimes (OrbStack, Docker Desktop) forward container ports through
    # their own process — they will always show up on our ports. Not a conflict.
    local docker_runtimes="OrbStack|com.docker|dockerd|Docker"

    if command -v lsof &>/dev/null; then
        local process
        process=$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==2 {print $1}')
        if [[ -n "$process" ]] && ! echo "$process" | grep -qE "$docker_runtimes"; then
            warn "Port $port ($service) is already in use by: $process"
            return 1
        fi
    elif command -v ss &>/dev/null; then
        local process
        process=$(ss -tlnp 2>/dev/null | grep ":$port " | sed 's/.*users:(("\([^"]*\)".*/\1/')
        if [[ -n "$process" ]] && ! echo "$process" | grep -qE "$docker_runtimes"; then
            warn "Port $port ($service) is already in use by: $process"
            return 1
        fi
    fi
    return 0
}

PORT_CONFLICT=false
check_port 5432 "PostgreSQL" || PORT_CONFLICT=true
check_port 8000 "Backend"    || PORT_CONFLICT=true
check_port 5173 "Frontend"   || PORT_CONFLICT=true

if [[ "$PORT_CONFLICT" == "true" ]]; then
    echo ""
    warn "Port conflict detected! Options:"
    warn "  1. Stop the conflicting process"
    warn "  2. Change ports in docker-compose.yml"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Aborted due to port conflict"
        exit 1
    fi
fi

# ==============================================================================
# CONTAINER MODE (read early — needed before the "already running" branch)
# ==============================================================================

CONTAINER_PREFS_FILE="$SCRIPT_DIR/.aida/container-preference"
CONTAINER_MODE=$(cat "$CONTAINER_PREFS_FILE" 2>/dev/null || echo "aida-pentest")

# ==============================================================================
# CHECK IF ALREADY RUNNING
# ==============================================================================

CONTAINERS_RUNNING=$($COMPOSE_CMD ps --status running -q 2>/dev/null | wc -l | tr -d ' ')

if [[ "$CONTAINERS_RUNNING" -ge 3 ]]; then
    # Still build — cache makes it instant if nothing changed, but picks up
    # any Dockerfile edits automatically without needing --build.
    if [[ "$CONTAINER_MODE" == "aida-pentest" ]]; then
        $COMPOSE_CMD build --quiet
    else
        $COMPOSE_CMD build --quiet backend frontend
    fi
    log "AIDA is already running!"
    echo ""
    $COMPOSE_CMD ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    log "Frontend: http://localhost:5173"
    log "Backend:  http://localhost:8000"
    echo ""
    exit 0
fi

# ==============================================================================
# ENVIRONMENT FILES (Quick)
# ==============================================================================

if [[ ! -f backend/.env ]]; then
    if [[ -f backend/.env.docker ]]; then
        cp backend/.env.docker backend/.env
        log "Created backend/.env"
    elif [[ -f backend/.env.example ]]; then
        cp backend/.env.example backend/.env
        log "Created backend/.env from example"
    fi
fi

if [[ ! -f frontend/.env ]]; then
    echo "VITE_API_URL=http://localhost:8000/api" > frontend/.env
    log "Created frontend/.env"
fi

# ==============================================================================
# FIRST-RUN: CONTAINER MODE SELECTION
# ==============================================================================

mkdir -p "$SCRIPT_DIR/.aida"

if [[ ! -f "$CONTAINER_PREFS_FILE" ]]; then
    section "First-Run Setup"
    echo ""
    echo "  AIDA needs a pentesting container to run security tools."
    echo ""
    echo "  [1] aida-pentest  (Recommended)"
    echo "      Built-in, managed by AIDA — starts automatically with ./start.sh"
    echo "      Size: ~2 GB |  Tools: nmap, ffuf, gobuster, sqlmap, nikto..."
    echo ""
    echo "  [2] Exegol"
    echo "      Third-party, requires separate install: https://docs.exegol.com"
    echo "      Size: ~20-40 GB  |  Tools: ~400+ security tools"
    echo ""
    echo "  You can always switch containers in Settings."
    echo ""
    read -p "  Your choice [1/2, default=1]: " -n 1 -r CONTAINER_CHOICE
    echo ""
    echo ""

    if [[ "$CONTAINER_CHOICE" == "2" ]]; then
        echo "exegol" > "$CONTAINER_PREFS_FILE"
        warn "Exegol mode selected."
        warn "Make sure Exegol is installed and a container is running before using AIDA:"
        warn "  Install: https://docs.exegol.com/first-install"
        warn "  Start:   exegol start aida"
        echo ""
    else
        echo "aida-pentest" > "$CONTAINER_PREFS_FILE"
        log "aida-pentest selected — the built-in container will start automatically."
    fi
    # Re-read now that the file exists
    CONTAINER_MODE=$(cat "$CONTAINER_PREFS_FILE" 2>/dev/null || echo "aida-pentest")
fi

# ==============================================================================
# PYTHON ENVIRONMENTS (Only if missing)
# ==============================================================================

if [[ "$SKIP_CHECKS" == "false" ]]; then
    # Find Python 3.10+
    PYTHON_CMD="python3"
    for py in python3.13 python3.12 python3.11 python3.10; do
        if command -v $py &> /dev/null; then
            PYTHON_CMD=$py
            break
        fi
    done

    # CLI venv
    if [[ ! -f ".venv/bin/python" ]]; then
        log "Creating CLI virtual environment..."
        $PYTHON_CMD -m venv .venv
        .venv/bin/pip install -q --upgrade pip
        [[ -f requirements.txt ]] && .venv/bin/pip install -q -r requirements.txt
        log "CLI environment ready"
    fi

    # Backend venv (for MCP server)
    if [[ ! -f "backend/venv/bin/python" ]]; then
        log "Creating backend virtual environment..."
        $PYTHON_CMD -m venv backend/venv
        backend/venv/bin/pip install -q --upgrade pip
        [[ -f backend/requirements.txt ]] && backend/venv/bin/pip install -q -r backend/requirements.txt
        log "Backend environment ready"
    fi
fi

# ==============================================================================
# DOCKER - Smart Build
# ==============================================================================

section "Docker Containers"

# Check for orphan containers from other projects with same names
ORPHAN_POSTGRES=$(docker ps -a --format "{{.Names}}" | grep "^aida_postgres$" || true)
ORPHAN_BACKEND=$(docker ps -a --format "{{.Names}}" | grep "^aida_backend$" || true)
ORPHAN_FRONTEND=$(docker ps -a --format "{{.Names}}" | grep "^aida_frontend$" || true)

# Check if these containers belong to our project
OUR_CONTAINERS=$($COMPOSE_CMD ps -a -q 2>/dev/null | wc -l | tr -d ' ')

if [[ -n "$ORPHAN_POSTGRES" || -n "$ORPHAN_BACKEND" || -n "$ORPHAN_FRONTEND" ]] && [[ "$OUR_CONTAINERS" -eq 0 ]]; then
    warn "Found containers from another project with same names"
    log "Removing orphan containers..."
    docker rm -f aida_postgres aida_backend aida_frontend 2>/dev/null || true
    log "Orphan containers removed"
fi

# Check if volume exists but belongs to another project - recreate it for this project
VOLUME_EXISTS=$(docker volume ls -q | grep "^aida_postgres_data$" || true)
if [[ -n "$VOLUME_EXISTS" ]]; then
    # Volume exists - check if it's labeled for another project
    VOLUME_PROJECT=$(docker volume inspect aida_postgres_data --format '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null || true)
    if [[ -n "$VOLUME_PROJECT" && "$VOLUME_PROJECT" != "aida" ]]; then
        log "Adopting existing postgres volume from project '$VOLUME_PROJECT'"
        # Remove old labels by recreating volume metadata (data preserved)
        # Docker compose will re-label it on next up
    fi
fi

# Always build — Docker layer cache makes this instant when nothing changed.
# This ensures Dockerfile changes (e.g. node_modules cache) are picked up
# automatically without needing --build.
if [[ "$CONTAINER_MODE" == "aida-pentest" ]]; then
    log "Building Docker images..."
    $COMPOSE_CMD build --quiet
else
    log "Building Docker images..."
    $COMPOSE_CMD build --quiet backend frontend
fi

# ==============================================================================
# START CONTAINERS
# ==============================================================================

# Check current state
RUNNING_CONTAINERS=$($COMPOSE_CMD ps --status running -q 2>/dev/null | wc -l | tr -d ' ')

if [[ "$RUNNING_CONTAINERS" -ge 3 ]]; then
    log "Containers already running"
else
    # Always use 'up -d' instead of 'start':
    # - recreates containers if the image/config changed (e.g. coming back from prod/LAN mode)
    # - creates fresh containers if they don't exist
    # - does nothing if already running
    log "Starting containers..."
    if [[ "$CONTAINER_MODE" == "aida-pentest" ]]; then
        $COMPOSE_CMD up -d --remove-orphans 2>&1 | grep -v "already exists but was created for project" || true
    else
        $COMPOSE_CMD up -d --remove-orphans postgres backend frontend 2>&1 | grep -v "already exists but was created for project" || true
    fi
fi

# ==============================================================================
# WAIT FOR SERVICES
# ==============================================================================

section "Waiting for Services"

wait_for_service() {
    local name=$1
    local check_cmd=$2
    local max_wait=${3:-30}
    local i=0

    printf "  %-12s " "$name..."
    while ! eval "$check_cmd" &>/dev/null; do
        ((i++))
        if [[ $i -ge $max_wait ]]; then
            echo -e "${RED}TIMEOUT${NC}"
            return 1
        fi
        sleep 1
    done
    echo -e "${GREEN}Ready${NC}"
}

wait_for_service "PostgreSQL" "$COMPOSE_CMD exec -T postgres pg_isready -U aida" 30
wait_for_service "Backend"    "curl -sf http://localhost:8000/health"              60
wait_for_service "Frontend"   "curl -sf http://localhost:5173"                     120

# ==============================================================================
# HOST HELPER (Background)
# ==============================================================================

pkill -f "tools/helper.py" 2>/dev/null || true
pkill -f "folder_opener.py" 2>/dev/null || true  # legacy name, just in case
if [[ -f "$SCRIPT_DIR/tools/helper.py" ]]; then
    python3 "$SCRIPT_DIR/tools/helper.py" &>/dev/null &
fi

# ==============================================================================
# PENTEST CONTAINER STATUS
# ==============================================================================

if [[ "$CONTAINER_MODE" == "exegol" ]]; then
    EXEGOL_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "^exegol-" || true)
    if [[ -n "$EXEGOL_RUNNING" ]]; then
        log "Exegol container: $EXEGOL_RUNNING"
    fi
    # No warning if Exegol isn't running — user manages it separately
else
    PENTEST_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | grep "^aida-pentest$" || true)
    if [[ -z "$PENTEST_RUNNING" ]]; then
        warn "aida-pentest not running — starting..."
        $COMPOSE_CMD up -d aida-pentest 2>&1 | grep -v "already" || true
    else
        log "Pentesting container: aida-pentest"
    fi
fi

# ==============================================================================
# SUCCESS
# ==============================================================================

section "AIDA Ready"

echo ""
log "Frontend:  http://localhost:5173"
log "Backend:   http://localhost:8000"
log "API Docs:  http://localhost:8000/docs"
echo ""
$COMPOSE_CMD ps --format "table {{.Name}}\t{{.Status}}"
echo ""
