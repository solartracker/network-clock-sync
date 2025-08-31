#!/bin/bash
################################################################################
# install.sh
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
#
################################################################################
set -e

PROJECT_DIR="$HOME/network-clock-sync"
SERVICE_NAME="network-clock-sync"

# Dependencies with minimum versions
declare -A dependencies=(
    [nmap]="7.93+dfsg1-1"
    [ipcalc]="0.42-2"
)

needs_update=false

# Check dependencies
for pkg in "${!dependencies[@]}"; do
    min_version="${dependencies[$pkg]}"
    if dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null; then
        installed_version=$(dpkg-query -W -f='${Version}' "$pkg")
        if ! dpkg --compare-versions "$installed_version" ge "$min_version"; then
            echo "$pkg ($installed_version) is older than required ($min_version)"
            needs_update=true
        fi
    else
        echo "$pkg is not installed"
        needs_update=true
    fi
done

# Run apt update once if needed, then install missing/outdated packages
if [ "$needs_update" = true ]; then
    echo "Updating package lists..."
    sudo apt update
    for pkg in "${!dependencies[@]}"; do
        min_version="${dependencies[$pkg]}"
        if ! dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || \
           ! dpkg --compare-versions "$(dpkg-query -W -f='${Version}' "$pkg")" ge "$min_version"; then
            echo "Installing/upgrading $pkg..."
            sudo apt install -y "$pkg"
        fi
    done
fi

# Install files explicitly, one line per file
echo "Installing binaries..."
sudo install -m 755 -o root -g root "$PROJECT_DIR/usr/local/bin/network-clock-sync.sh" /usr/local/bin/network-clock-sync.sh

echo "Installing systemd service..."
sudo install -m 644 -o root -g root "$PROJECT_DIR/etc/systemd/system/network-clock-sync.service" /etc/systemd/system/network-clock-sync.service

# Reload systemd and enable/start service
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "Enabling and starting service..."
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo "Installation complete!"

