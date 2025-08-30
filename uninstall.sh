#!/bin/bash
################################################################################
# uninstall.sh
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
##################################################################################
set -e

SERVICE_NAME="network-clock-sync"

echo "Stopping and disabling service..."
sudo systemctl stop "$SERVICE_NAME" || true
sudo systemctl disable "$SERVICE_NAME" || true

echo "Removing binaries..."
sudo rm -f /usr/local/bin/network-clock-sync.sh

echo "Removing systemd service..."
sudo rm -f /etc/systemd/system/network-clock-sync.service

echo "Removing service-generated files..."
sudo rm -f /var/lib/network-clock-sync/host_ip
sudo rm -f /var/log/network-clock-sync.log

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Uninstallation complete!"

