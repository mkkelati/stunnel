#!/bin/bash

# Quick Install Script for SSH User Manager for Stunnel
# Downloads complete repository and runs installation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}SSH User Manager for Stunnel - Quick Installer${NC}"
echo "=============================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: curl -sSL https://raw.githubusercontent.com/mkkelati/stunnel/main/quick_install.sh | sudo bash"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo -e "${BLUE}Downloading SSH User Manager repository...${NC}"

# Download repository
if command -v wget >/dev/null 2>&1; then
    wget -q https://github.com/mkkelati/stunnel/archive/refs/heads/main.tar.gz -O stunnel.tar.gz
elif command -v curl >/dev/null 2>&1; then
    curl -sSL https://github.com/mkkelati/stunnel/archive/refs/heads/main.tar.gz -o stunnel.tar.gz
else
    echo -e "${RED}Error: Neither wget nor curl is available${NC}"
    exit 1
fi

# Verify download
if [[ ! -f "stunnel.tar.gz" ]]; then
    echo -e "${RED}Error: Failed to download repository${NC}"
    exit 1
fi

echo -e "${GREEN}Repository downloaded successfully${NC}"

# Extract repository
echo -e "${BLUE}Extracting files...${NC}"
tar -xzf stunnel.tar.gz
cd stunnel-main

# Verify essential files exist
for file in install.sh ssh_user_manager.sh generate_ssl_cert.sh monitor_cleanup.sh menu.sh stunnel.conf; do
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: Required file $file not found in repository${NC}"
        exit 1
    fi
done

echo -e "${GREEN}All files extracted successfully${NC}"

# Make installer executable
chmod +x install.sh

# Run installation
echo -e "${BLUE}Starting installation...${NC}"
echo ""
./install.sh install

# Check installation result
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Type 'menu' to start the interactive interface"
    echo "2. Create your first user through the menu"
    echo "3. Configure HTTP Injector with your server details"
    echo ""
    echo -e "${BLUE}Quick commands:${NC}"
    echo "  menu                    # Interactive menu system"
    echo "  ssh-user-manager list   # List users"
    echo "  ssh-monitor status      # Check system status"
else
    echo -e "${RED}Installation failed. Please check the logs above.${NC}"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Setup complete! The system is ready to use.${NC}"
