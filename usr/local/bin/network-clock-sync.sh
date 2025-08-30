#!/bin/bash
################################################################################
# network-clock-sync.sh
#
# Sets the system clock from an HTTP server on the local network. 
# 
# Copyright (C) 2025 Richard Elwell
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
##################################################################################
#set -x # uncomment for debugging
set -euo pipefail

CACHE_FILE="/var/lib/network-clock-sync/host_ip"
LOG_FILE="/var/log/network-clock-sync.log"
MAX_LOG_LINES=200

# Find all HTTP hosts on the local network that use timestamped HTTP headers
find_http_hosts() {
    echo "Port scanning local network for HTTP hosts..." >&2
    NETWORK_CIDR=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | while read cidr; do ipcalc -n $cidr | awk '/Network/ {print $2}'; done)

    if [ -z "$NETWORK_CIDR" ]; then
        echo "Could not determine IP network range." >&2
        exit 1
    fi

    # Port scan for remote HTTP hosts
    MY_IP=$(ip -4 addr show scope global | awk '/inet/ {print $2}' | cut -d/ -f1)
    nmap -p80 --open -oG - --exclude "$MY_IP" $NETWORK_CIDR | awk '/80\/open/ {print $2}' | sudo tee /tmp/http_hosts.txt >/dev/null
    if [ ! -s /tmp/http_hosts.txt ]; then
        echo "No remote HTTP hosts found on network." >&2
        exit 1
    fi

    # Get list of remote HTTP hosts that have a timestamp in the HTTP header
    # Run concurrently, collect results in one file and sort the list on timestamp in descending order
    xargs -a /tmp/http_hosts.txt -P20 -I{} sh -c '
      ip="{}"
      timestamp=$(curl -sI --max-time 2 http://$ip/ | grep -Poi -m1 "^Date:[[:space:]]*\K.*")
      if [ -n "$timestamp" ]; then
        utc=$(date -u -d "$timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        [ -n "$utc" ] && echo "$ip $utc"
      fi
    ' | sort -t' ' -k2,2r | sudo tee /tmp/httptime_hosts.txt >/dev/null

    if [ ! -s /tmp/httptime_hosts.txt ]; then
        echo "No time sources found on the local network." >&2
        exit 1
    fi
}

# Find the HTTP host with the latest clock time
get_latest_clocktime() {
    find_http_hosts

    # Use the first line because the list is sorted
    read -r ip ts </tmp/httptime_hosts.txt

    if [ -z "$ip" ]; then
        echo "No reachable HTTP hosts found." >&2
        exit 1
    fi

    # Cache the chosen HTTP host
    sudo mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$ip" | sudo tee "$CACHE_FILE" >/dev/null

    echo "$ip|$ts"
}

# Load cached host if available
if [ -f "$CACHE_FILE" ]; then
    read -r cached_host <"$CACHE_FILE"
    echo "Using cached host IP: $cached_host"
    timestamp=""
else
    cached_host=""
fi

# Verify cached host
host_ip="$cached_host"
if [ -z "$host_ip" ]; then
    result=$(get_latest_clocktime)
    host_ip="${result%%|*}"
    timestamp="${result#*|}"
fi

# Get timestamp from chosen HTTP host
if [ -z "$timestamp" ]; then
    timestamp=$( curl -sI --max-time 2 http://$host_ip/ | grep -Poi -m1 "^Date:\s*\K.*" || true )

    if [ -z "$timestamp" ]; then
        echo "Cached HTTP host $host_ip unreachable. Rescanning..."
        result=$(get_latest_clocktime)
        host_ip="${result%%|*}"
        timestamp="${result#*|}"

        if [ -z "$timestamp" ]; then
            echo "No HTTP hosts were found on the local network.  Exiting..."
            exit 1
        fi
    fi
fi

utc_host_sec=$(date -d "$timestamp" -u +"%s")
utc_system_sec=$(date -u +"%s")

# Compare with 60-second tolerance
if (( utc_host_sec < utc_system_sec + 60 )); then
    echo "Your system clock appears to be set correctly relative to the remote HTTP host $host_ip"
    clock_updated=0
else
    sudo date -u -s "@$utc_host_sec" >/dev/null
    echo "Your system clock is slow relative to the remote HTTP host $host_ip"
    clock_updated=1
fi

# Display human-readable times
utc_host=$(date -d "@$utc_host_sec" +"%Y-%m-%d %H:%M:%S %Z")
utc_system=$(date -d "@$utc_system_sec" +"%Y-%m-%d %H:%M:%S %Z")

echo "Current time on remote HTTP host: $utc_host"
echo "Current time on this system:      $utc_system"
[ $clock_updated == 1 ] && echo "Changed your system clock to:     $utc_host"

# Log the check with rotation (keep last MAX_LOG_LINES entries)
sudo mkdir -p "$(dirname "$LOG_FILE")"
log_entry="$(date +"%Y-%m-%d %H:%M:%S %Z") | Remote Host: $host_ip | Remote Time: $utc_host | System Time: $utc_system | Clock Updated: $clock_updated"
echo "$log_entry" | sudo tee -a "$LOG_FILE" >/dev/null
tail -n "$MAX_LOG_LINES" "$LOG_FILE" | sudo tee "${LOG_FILE}.tmp" >/dev/null && sudo mv "${LOG_FILE}.tmp" "$LOG_FILE"

