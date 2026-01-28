#!/bin/bash
set -euo pipefail

# Colors for better UX (matching restore.sh style)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Resolve project root relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/vps/docker/nextcloud.yml.j2"
CADDY_FILE="$SCRIPT_DIR/pyinfra/stages/2-caddy.py"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
TERRAFORM_FILE="$SCRIPT_DIR/terraform/main.tf"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm() {
    local prompt="$1"
    local response
    read -rp "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy] ]]
}

prompt_deploy() {
    echo ""
    if confirm "Deploy this change now?"; then
        log_info "Running deployment..."
        cd "$SCRIPT_DIR"
        uv run pyinfra/configure_vps.py
    fi
}

# --- Version extraction ---

get_nextcloud_version() {
    grep 'image: nextcloud:' "$COMPOSE_FILE" | head -1 | sed 's/.*nextcloud://' | tr -d '[:space:]'
}

get_postgres_version() {
    grep 'image: postgres:' "$COMPOSE_FILE" | sed 's/.*postgres://' | sed 's/-.*//' | tr -d '[:space:]'
}

get_redis_version() {
    grep 'image: redis:' "$COMPOSE_FILE" | sed 's/.*redis://' | sed 's/-.*//' | tr -d '[:space:]'
}

get_go_version() {
    grep 'GO_VERSION=' "$ENV_EXAMPLE" | head -1 | sed 's/.*GO_VERSION=//'
}

get_xcaddy_version() {
    grep 'xcaddy/releases/download/' "$CADDY_FILE" | grep -o 'v[0-9][0-9.]*' | head -1
}

get_caddy_dns_version() {
    grep 'caddy-dns/hetzner' "$CADDY_FILE" | grep -o '@[^ "]*' | sed 's/@//'
}

get_terraform_version() {
    grep 'required_version' "$TERRAFORM_FILE" | grep -o '"[^"]*"' | tr -d '"'
}

# --- Version bumping ---

bump_nextcloud() {
    local old="$1" new="$2"
    log_info "Updating Nextcloud: $old -> $new"
    sed -i '' "s|image: nextcloud:${old}|image: nextcloud:${new}|g" "$COMPOSE_FILE"
    log_success "Updated nextcloud image tag in $(basename "$COMPOSE_FILE")"
}

bump_postgres() {
    local old="$1" new="$2"
    log_info "Updating PostgreSQL: $old -> $new"
    sed -i '' "s|image: postgres:${old}-alpine|image: postgres:${new}-alpine|g" "$COMPOSE_FILE"
    log_success "Updated postgres image tag in $(basename "$COMPOSE_FILE")"
}

bump_redis() {
    local old="$1" new="$2"
    log_info "Updating Redis: $old -> $new"
    sed -i '' "s|image: redis:${old}-alpine|image: redis:${new}-alpine|g" "$COMPOSE_FILE"
    log_success "Updated redis image tag in $(basename "$COMPOSE_FILE")"
}

bump_go() {
    local old="$1" new="$2"
    log_info "Updating Go: $old -> $new"
    sed -i '' "s|GO_VERSION=${old}|GO_VERSION=${new}|g" "$ENV_EXAMPLE"
    sed -i '' "s|\"GO_VERSION\", \"${old}\"|\"GO_VERSION\", \"${new}\"|g" "$CADDY_FILE"
    log_success "Updated Go version in $(basename "$ENV_EXAMPLE") and $(basename "$CADDY_FILE")"
}

bump_xcaddy() {
    local old="$1" new="$2"
    log_info "Updating xcaddy: $old -> $new"
    # The version appears twice in the download URL: v0.4.5/xcaddy_0.4.5
    local old_bare="${old#v}"
    local new_bare="${new#v}"
    sed -i '' "s|xcaddy/releases/download/v${old_bare}/xcaddy_${old_bare}|xcaddy/releases/download/v${new_bare}/xcaddy_${new_bare}|g" "$CADDY_FILE"
    log_success "Updated xcaddy version in $(basename "$CADDY_FILE")"
}

bump_caddy_dns() {
    local old="$1" new="$2"
    log_info "Updating caddy-dns/hetzner: $old -> $new"
    sed -i '' "s|caddy-dns/hetzner/v2@${old}|caddy-dns/hetzner/v2@${new}|g" "$CADDY_FILE"
    log_success "Updated caddy-dns/hetzner version in $(basename "$CADDY_FILE")"
}

bump_terraform() {
    local old="$1" new="$2"
    log_info "Updating Terraform: $old -> $new"
    sed -i '' "s|required_version = \"${old}\"|required_version = \"${new}\"|g" "$TERRAFORM_FILE"
    log_success "Updated Terraform version in $(basename "$TERRAFORM_FILE")"
}

# --- Display ---

show_versions() {
    echo ""
    echo -e "${BOLD}Current pinned versions:${NC}"
    echo ""
    echo -e "  ${BOLD}Docker images${NC}"
    echo -e "    1) Nextcloud       $(get_nextcloud_version)"
    echo -e "    2) PostgreSQL      $(get_postgres_version)-alpine"
    echo -e "    3) Redis           $(get_redis_version)-alpine"
    echo ""
    echo -e "  ${BOLD}Build tools${NC}"
    echo -e "    4) Go              $(get_go_version)"
    echo -e "    5) xcaddy          $(get_xcaddy_version)"
    echo -e "    6) caddy-dns       $(get_caddy_dns_version)"
    echo ""
    echo -e "  ${BOLD}Infrastructure${NC}"
    echo -e "    7) Terraform       $(get_terraform_version)"
    echo ""
}

# --- Interactive menu ---

interactive_bump() {
    local choice="$1"
    local component old new

    case "$choice" in
        1) component="nextcloud";  old="$(get_nextcloud_version)" ;;
        2) component="postgres";   old="$(get_postgres_version)" ;;
        3) component="redis";      old="$(get_redis_version)" ;;
        4) component="go";         old="$(get_go_version)" ;;
        5) component="xcaddy";     old="$(get_xcaddy_version)" ;;
        6) component="caddy-dns";  old="$(get_caddy_dns_version)" ;;
        7) component="terraform";  old="$(get_terraform_version)" ;;
        *)
            log_error "Invalid choice: $choice"
            return 1
            ;;
    esac

    echo -e "Current ${BOLD}${component}${NC} version: ${YELLOW}${old}${NC}"
    read -rp "New version: " new

    if [[ -z "$new" ]]; then
        log_warning "No version provided, skipping."
        return 0
    fi

    if [[ "$old" == "$new" ]]; then
        log_warning "Version unchanged, skipping."
        return 0
    fi

    case "$component" in
        nextcloud)  bump_nextcloud "$old" "$new" ;;
        postgres)   bump_postgres "$old" "$new" ;;
        redis)      bump_redis "$old" "$new" ;;
        go)         bump_go "$old" "$new" ;;
        xcaddy)     bump_xcaddy "$old" "$new" ;;
        caddy-dns)  bump_caddy_dns "$old" "$new" ;;
        terraform)  bump_terraform "$old" "$new" ;;
    esac

    prompt_deploy
}

# --- CLI interface ---

usage() {
    echo ""
    echo -e "${BOLD}Usage:${NC} $(basename "$0") [command] [component] [version]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  list                       Show all current versions"
    echo "  set <component> <version>  Bump a component to a new version"
    echo "  (no arguments)             Interactive mode"
    echo ""
    echo -e "${BOLD}Components:${NC}"
    echo "  nextcloud, postgres, redis, go, xcaddy, caddy-dns, terraform"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $(basename "$0")                        # Interactive mode"
    echo "  $(basename "$0") list                    # Show versions"
    echo "  $(basename "$0") set nextcloud 33        # Bump Nextcloud to 33"
    echo "  $(basename "$0") set go 1.24.0           # Bump Go to 1.24.0"
    echo ""
}

cli_set() {
    local component="$1" new="$2"
    local old

    case "$component" in
        nextcloud)  old="$(get_nextcloud_version)";  bump_nextcloud "$old" "$new" ;;
        postgres)   old="$(get_postgres_version)";    bump_postgres "$old" "$new" ;;
        redis)      old="$(get_redis_version)";       bump_redis "$old" "$new" ;;
        go)         old="$(get_go_version)";          bump_go "$old" "$new" ;;
        xcaddy)     old="$(get_xcaddy_version)";      bump_xcaddy "$old" "$new" ;;
        caddy-dns)  old="$(get_caddy_dns_version)";   bump_caddy_dns "$old" "$new" ;;
        terraform)  old="$(get_terraform_version)";   bump_terraform "$old" "$new" ;;
        *)
            log_error "Unknown component: $component"
            usage
            exit 1
            ;;
    esac

    prompt_deploy
}

main() {
    if [[ $# -ge 1 ]]; then
        case "$1" in
            list)
                show_versions
                ;;
            set)
                if [[ $# -lt 3 ]]; then
                    log_error "Usage: $(basename "$0") set <component> <version>"
                    exit 1
                fi
                cli_set "$2" "$3"
                ;;
            -h|--help|help)
                usage
                ;;
            *)
                log_error "Unknown command: $1"
                usage
                exit 1
                ;;
        esac
    else
        # Interactive mode
        show_versions
        echo -e "Enter a number to bump a version, or ${BOLD}q${NC} to quit."
        echo ""

        while true; do
            read -rp "> " choice
            case "$choice" in
                q|Q|quit|exit) break ;;
                [1-7]) interactive_bump "$choice"; echo "" ;;
                "") ;;
                *) log_error "Enter a number (1-7) or q to quit." ;;
            esac
        done
    fi
}

main "$@"
