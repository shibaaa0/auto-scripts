#!/usr/bin/env bash
# quick_nmap_ports_compat.sh - run nmap default scan, do NOT persist results to disk long-term,
#                            show only: PORT    STATE    SERVICE
set -euo pipefail

# colors (optional)
GREEN="\033[1;32m"
CYAN="\033[1;36m"
RESET="\033[0m"

has_cmd(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "Error: $*" >&2; exit 1; }

spinner(){
    local pid=$1
    local delay=0.12
    local spinstr='|/-\'
    printf " "
    while kill -0 "$pid" 2>/dev/null; do
        for i in 0 1 2 3; do
            printf "\b${spinstr:i:1}"
            sleep $delay
        done
    done
    printf "\b"
}

check_requirements(){
    has_cmd nmap || die "nmap not found. Install nmap and retry."
    has_cmd mktemp || die "mktemp required."
}

print_header(){
    clear
    echo -e "${CYAN}=== SCAN PORTS ===${RESET}"
    echo
}

read_target(){
    local t=""
    while [[ -z "$t" ]]; do
        read -rp "Target (IP or hostname) > " t
    done
    echo "$t"
}

# main
check_requirements
print_header
target=$(read_target)

# Use an in-RAM temporary file (prefer /dev/shm). This is ephemeral and removed immediately.
if [[ -d /dev/shm && -w /dev/shm ]]; then
    tmp="$(mktemp /dev/shm/pretty_nmap.XXXXXX)"
else
    tmp="$(mktemp /tmp/pretty_nmap.XXXXXX)"
fi

echo "Scanning ${target} with nmap (default). Please wait..."
# run nmap producing grepable output to the tmp buffer
nmap "$target" -oG - > "$tmp" 2>&1 &
nmap_pid=$!
spinner "$nmap_pid"
wait "$nmap_pid" || true

# Print header
printf "%-10s %-8s %s\n" "PORT" "STATE" "SERVICE"
printf "%-10s %-8s %s\n" "----" "-----" "-------"

# Parse grepable output using pure bash
while IFS= read -r line; do
    # Only process lines that begin with "Host:"
    case "$line" in
        Host:*)
            # Get the "Ports: ..." portion (if any)
            # Example line:
            # Host: 127.0.0.1 ()    Ports: 22/open/tcp//ssh///,80/closed/tcp//http///  Ignored State: closed (998)
            if echo "$line" | grep -q "Ports:"; then
                # Extract substring after "Ports: "
                ports_field="${line#*Ports: }"
                # Remove trailing "  Ignored State: ..." if present
                ports_field="${ports_field%%  Ignored State:*}"
                # Split by comma
                IFS=',' read -ra port_items <<< "$ports_field"
                for item in "${port_items[@]}"; do
                    # trim leading/trailing spaces
                    item="${item#"${item%%[![:space:]]*}"}"
                    item="${item%"${item##*[![:space:]]}"}"
                    # parts separated by '/'
                    IFS='/' read -ra parts <<< "$item"
                    portnum="${parts[0]}"
                    state="${parts[1]}"
                    proto="${parts[2]}"
                    # try to get service: appears after double slash: e.g. ...//ssh///
                    svc=""
                    # find // and capture up to next /
                    if [[ "$item" =~ \\/\/([^\/]*) ]]; then
                        svc="${BASH_REMATCH[1]}"
                    else
                        # fallback to parts[4] if exists
                        svc="${parts[4]:-}"
                    fi
                    if [[ "$state" == "open" ]]; then
                        printf "%-10s %-8s %s\n" "${portnum}/${proto}" "$state" "$svc"
                    fi
                done
            fi
            ;;
        *) ;;
    esac
done < "$tmp"

# remove temporary buffer
rm -f "$tmp"

echo
echo -e "${GREEN}Done.${RESET}"
