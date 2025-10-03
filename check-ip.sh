#!/usr/bin/env bash
# check_ip.sh - show private (local) and public IPv4, per-interface, gateway info

set -uo pipefail

# color
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"

die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Get IPv4 addresses per interface
list_local_ips() {
    if has_cmd ip; then
        echo -e "${CYAN}Local IPv4 addresses (per interface):${RESET}"
        ip -o -4 addr show scope global | while read -r _ ifname fam addr _; do
            addr_only=$(echo "$addr" | awk '{print $1}')
            printf "  %-12s %s\n" "$ifname" "$addr_only"
        done
        if ! ip -o -4 addr show scope global | grep -q .; then
            echo "  (no IPv4 addresses found)"
        fi
    elif has_cmd ifconfig; then
        echo -e "${CYAN}Local IPv4 addresses (per interface):${RESET}"
        ifconfig | awk '/flags|inet /{print}' | sed 's/flags=.*$//' | while read -r line; do
            echo "  $line"
        done
    else
        echo "No 'ip' or 'ifconfig' command found to list interfaces."
    fi
}

# Try multiple services to fetch public IPv4
get_public_ip() {
    local services_v4=( "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com" )

    for url in "${services_v4[@]}"; do
        if has_cmd curl; then
            ip=$(curl -s --max-time 5 -4 "$url" 2>/dev/null || true)
        elif has_cmd wget; then
            ip=$(wget -qO- --timeout=5 --inet4-only "$url" 2>/dev/null || true)
        else
            ip=""
        fi
        if [[ -n "$ip" ]]; then
            echo "$ip" && return 0
        fi
    done

    # fallback using dig+opendns if available
    if has_cmd dig; then
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || true)
        if [[ -n "$ip" ]]; then
            echo "$ip" && return 0
        fi
    fi

    return 1
}

# Default gateway
get_gateway() {
    if has_cmd ip; then
        gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
        if [[ -n "$gw" ]]; then
            echo "$gw"
            return
        fi
    fi
    if has_cmd route; then
        gw=$(route -n 2>/dev/null | awk '$4=="UG" {print $2; exit}')
        if [[ -n "$gw" ]]; then
            echo "$gw"
            return
        fi
    fi
    echo "N/A"
}

# Check if an IPv4 is private (RFC1918 + link-local)
is_private_ipv4() {
    ip="$1"
    ip="${ip%%/*}"
    case "$ip" in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
        169.254.*) return 0 ;; # link-local
        *) return 1 ;;
    esac
}

# Pretty print results
echo -e "${GREEN}=== IPv4 CHECKER ===${RESET}"
echo

list_local_ips
echo

gw=$(get_gateway)
echo -e "${YELLOW}Default gateway:${RESET} $gw"
echo

echo -e "${YELLOW}Public IPv4:${RESET} \c"
if pub4=$(get_public_ip); then
    echo -e "$pub4"
else
    echo -e "${RED}Unable to determine public IPv4 (no response).${RESET}"
fi

echo

# Summarize local IPv4 addresses and whether they look private
if has_cmd ip; then
    echo -e "${CYAN}Local IPv4 summary:${RESET}"
    ip -4 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}' | while read -r line; do
        iface=$(echo "$line" | cut -d: -f1)
        addr=$(echo "$line" | cut -d' ' -f2)
        if is_private_ipv4 "$addr"; then
            status="(private)"
        else
            status="(public?)"
        fi
        printf "  %-12s %-20s %s\n" "$iface" "$addr" "$status"
    done
fi

echo
first_local_ipv4=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -n1 || true)
if [[ -n "$first_local_ipv4" && -n "${pub4:-}" ]]; then
    if is_private_ipv4 "$first_local_ipv4"; then
        echo -e "${YELLOW}NAT hint:${RESET} Your machine has a private IPv4 ($first_local_ipv4) but public IPv4 is $pub4 -> likely behind NAT."
    else
        echo -e "${YELLOW}NAT hint:${RESET} Your machine appears to have a global IPv4 address."
    fi
fi

echo
echo -e "${GREEN}Done.${RESET}"
