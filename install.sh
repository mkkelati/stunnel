#!/bin/bash

# SSH User Manager for Stunnel - Installation Script
# Installs and configures the complete system with TLSv1.3 security

# Configuration
INSTALL_DIR="/opt/ssh-user-manager"
SERVICE_NAME="ssh-user-manager"
STUNNEL_CONFIG_DIR="/etc/stunnel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
LOG_FILE="/var/log/ssh_user_manager_install.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        OS="unknown"
    fi
    
    log_message "${BLUE}Detected OS: $OS $VERSION${NC}"
}

# Install dependencies
install_dependencies() {
    log_message "${BLUE}Installing dependencies...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y stunnel4 openssh-server openssl curl wget net-tools mailutils cron
            
            # Enable and start SSH
            systemctl enable ssh
            systemctl start ssh
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y stunnel openssh-server openssl curl wget net-tools mailx cronie
            else
                yum install -y stunnel openssh-server openssl curl wget net-tools mailx cronie
            fi
            
            # Enable and start SSH
            systemctl enable sshd
            systemctl start sshd
            ;;
        *)
            log_message "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        log_message "${GREEN}Dependencies installed successfully${NC}"
    else
        log_message "${RED}Failed to install dependencies${NC}"
        exit 1
    fi
}

# Create installation directory
create_install_dir() {
    log_message "${BLUE}Creating installation directory...${NC}"
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$STUNNEL_CONFIG_DIR"
    mkdir -p "/var/log/stunnel"
    mkdir -p "/var/run/stunnel"
    
    chmod 755 "$INSTALL_DIR"
    chmod 700 "$STUNNEL_CONFIG_DIR"
    chmod 755 "/var/log/stunnel"
    chmod 755 "/var/run/stunnel"
    
    log_message "${GREEN}Installation directory created: $INSTALL_DIR${NC}"
}

# Download and copy scripts to installation directory
copy_scripts() {
    log_message "${BLUE}Downloading and copying scripts...${NC}"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local github_base="https://raw.githubusercontent.com/mkkelati/stunnel/main"
    
    # Check if files exist locally (manual installation)
    if [[ -f "$script_dir/ssh_user_manager.sh" ]]; then
        log_message "${BLUE}Using local files...${NC}"
        # Copy main scripts
        cp "$script_dir/ssh_user_manager.sh" "$INSTALL_DIR/"
        cp "$script_dir/generate_ssl_cert.sh" "$INSTALL_DIR/"
        cp "$script_dir/monitor_cleanup.sh" "$INSTALL_DIR/"
        cp "$script_dir/menu.sh" "$INSTALL_DIR/"
        cp "$script_dir/stunnel.conf" "$INSTALL_DIR/"
    else
        log_message "${BLUE}Downloading files from GitHub...${NC}"
        # Download main scripts from GitHub
        curl -sSL "$github_base/ssh_user_manager.sh" -o "$INSTALL_DIR/ssh_user_manager.sh"
        curl -sSL "$github_base/generate_ssl_cert.sh" -o "$INSTALL_DIR/generate_ssl_cert.sh"
        curl -sSL "$github_base/monitor_cleanup.sh" -o "$INSTALL_DIR/monitor_cleanup.sh"
        curl -sSL "$github_base/menu.sh" -o "$INSTALL_DIR/menu.sh"
        curl -sSL "$github_base/stunnel.conf" -o "$INSTALL_DIR/stunnel.conf"
        
        # Verify downloads
        for file in ssh_user_manager.sh generate_ssl_cert.sh monitor_cleanup.sh menu.sh stunnel.conf; do
            if [[ ! -f "$INSTALL_DIR/$file" ]]; then
                log_message "${RED}Failed to download $file${NC}"
                exit 1
            fi
        done
        
        log_message "${GREEN}All files downloaded successfully${NC}"
    fi
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR"/*.sh
    
    # Copy stunnel config
    cp "$INSTALL_DIR/stunnel.conf" "$STUNNEL_CONFIG_DIR/"
    
    log_message "${GREEN}Scripts setup completed successfully${NC}"
}

# Generate SSL certificates
generate_certificates() {
    log_message "${BLUE}Generating SSL certificates...${NC}"
    
    # Run certificate generation script in auto mode
    "$INSTALL_DIR/generate_ssl_cert.sh" auto
    
    if [[ $? -eq 0 ]]; then
        log_message "${GREEN}SSL certificates generated successfully${NC}"
    else
        log_message "${RED}Failed to generate SSL certificates${NC}"
        exit 1
    fi
}

# Configure stunnel service
configure_stunnel() {
    log_message "${BLUE}Configuring stunnel service...${NC}"
    
    # Create stunnel systemd service
    cat > "/etc/systemd/system/stunnel.service" << EOF
[Unit]
Description=SSL tunneling service
After=network.target

[Service]
Type=forking
PIDFile=/var/run/stunnel/stunnel.pid
ExecStart=/usr/bin/stunnel $STUNNEL_CONFIG_DIR/stunnel.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start stunnel
    systemctl daemon-reload
    systemctl enable stunnel
    systemctl start stunnel
    
    if systemctl is-active --quiet stunnel; then
        log_message "${GREEN}Stunnel service configured and started${NC}"
    else
        log_message "${RED}Failed to start stunnel service${NC}"
        systemctl status stunnel
        exit 1
    fi
}

# Configure SSH
configure_ssh() {
    log_message "${BLUE}Configuring SSH for security...${NC}"
    
    # Backup original sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Update SSH configuration for security
    cat >> /etc/ssh/sshd_config << EOF

# SSH User Manager Security Settings
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60
EOF

    # Test SSH configuration
    sshd -t
    if [[ $? -eq 0 ]]; then
        systemctl reload ssh || systemctl reload sshd
        log_message "${GREEN}SSH configuration updated${NC}"
    else
        log_message "${RED}SSH configuration test failed, restoring backup${NC}"
        mv /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        exit 1
    fi
}

# Configure firewall
configure_firewall() {
    log_message "${BLUE}Configuring firewall...${NC}"
    
    # Configure UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        ufw --force enable
        ufw allow 22/tcp
        ufw allow 443/tcp
        log_message "${GREEN}UFW firewall configured${NC}"
    
    # Configure firewalld (CentOS/RHEL/Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        systemctl enable firewalld
        systemctl start firewalld
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
        log_message "${GREEN}Firewalld configured${NC}"
    
    # Configure iptables (fallback)
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        
        # Save iptables rules
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
            iptables-save > /etc/sysconfig/iptables 2>/dev/null
        fi
        
        log_message "${GREEN}Iptables configured${NC}"
    else
        log_message "${YELLOW}No firewall management tool found, please configure manually${NC}"
    fi
}

# Create symbolic links
create_symlinks() {
    log_message "${BLUE}Creating symbolic links...${NC}"
    
    ln -sf "$INSTALL_DIR/ssh_user_manager.sh" "/usr/local/bin/ssh-user-manager"
    ln -sf "$INSTALL_DIR/generate_ssl_cert.sh" "/usr/local/bin/ssl-cert-manager"
    ln -sf "$INSTALL_DIR/monitor_cleanup.sh" "/usr/local/bin/ssh-monitor"
    ln -sf "$INSTALL_DIR/menu.sh" "/usr/local/bin/menu"
    
    log_message "${GREEN}Symbolic links created${NC}"
}

# Install monitoring cron job
install_monitoring() {
    log_message "${BLUE}Installing monitoring cron job...${NC}"
    
    "$INSTALL_DIR/monitor_cleanup.sh" install-cron "0 */6 * * *"
    
    if [[ $? -eq 0 ]]; then
        log_message "${GREEN}Monitoring cron job installed (every 6 hours)${NC}"
    else
        log_message "${RED}Failed to install monitoring cron job${NC}"
    fi
}

# Create default configuration
create_default_config() {
    log_message "${BLUE}Creating default configuration...${NC}"
    
    cat > "$INSTALL_DIR/manager.conf" << EOF
# SSH User Manager Configuration
MAX_USERS=50
DEFAULT_EXPIRE_DAYS=30
ALLOW_PASSWORD_AUTH=true
REQUIRE_KEY_AUTH=true
MIN_PASSWORD_LENGTH=12
STUNNEL_PORT=443
STUNNEL_CONFIG_PATH=$STUNNEL_CONFIG_DIR/stunnel.conf
EOF

    log_message "${GREEN}Default configuration created${NC}"
}

# Verify installation
verify_installation() {
    log_message "${BLUE}Verifying installation...${NC}"
    
    local errors=0
    
    # Check if services are running
    if ! systemctl is-active --quiet stunnel; then
        log_message "${RED}Stunnel service is not running${NC}"
        ((errors++))
    fi
    
    if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
        log_message "${RED}SSH service is not running${NC}"
        ((errors++))
    fi
    
    # Check if port 443 is listening
    if ! netstat -ln | grep -q ":443 "; then
        log_message "${RED}Port 443 is not listening${NC}"
        ((errors++))
    fi
    
    # Check if scripts are executable
    for script in ssh_user_manager.sh generate_ssl_cert.sh monitor_cleanup.sh; do
        if [[ ! -x "$INSTALL_DIR/$script" ]]; then
            log_message "${RED}Script $script is not executable${NC}"
            ((errors++))
        fi
    done
    
    # Check SSL certificate
    if [[ ! -f "$STUNNEL_CONFIG_DIR/stunnel.pem" ]]; then
        log_message "${RED}SSL certificate not found${NC}"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_message "${GREEN}Installation verification passed${NC}"
        return 0
    else
        log_message "${RED}Installation verification failed with $errors errors${NC}"
        return 1
    fi
}

# Show installation summary
show_summary() {
    log_message "${GREEN}Installation completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}SSH User Manager for Stunnel - Installation Summary${NC}"
    echo "=================================================="
    echo ""
    echo "Installation directory: $INSTALL_DIR"
    echo "Configuration file: $INSTALL_DIR/manager.conf"
    echo "Stunnel config: $STUNNEL_CONFIG_DIR/stunnel.conf"
    echo "SSL certificate: $STUNNEL_CONFIG_DIR/stunnel.pem"
    echo ""
    echo -e "${YELLOW}Available Commands:${NC}"
    echo "  menu                                    # Interactive menu system"
    echo "  ssh-user-manager create <username> [days] [--password]"
    echo "  ssh-user-manager delete <username>"
    echo "  ssh-user-manager list"
    echo "  ssl-cert-manager generate"
    echo "  ssh-monitor status"
    echo ""
    echo -e "${YELLOW}Usage Examples:${NC}"
    echo "  ssh-user-manager create john 30        # Create user for 30 days with key auth"
    echo "  ssh-user-manager create jane 7 --password  # Create user with password auth"
    echo "  ssh-user-manager list                   # List all users"
    echo ""
    echo -e "${YELLOW}Connection Information:${NC}"
    echo "  Port: 443 (SSL/TLS tunnel to SSH)"
    echo "  Protocol: TLSv1.3 with TLS_AES_256_GCM_SHA384"
    echo "  Connection command: ssh username@server_ip -p 443"
    echo ""
    echo -e "${YELLOW}Service Status:${NC}"
    
    if systemctl is-active --quiet stunnel; then
        echo -e "  Stunnel: ${GREEN}Running${NC}"
    else
        echo -e "  Stunnel: ${RED}Not Running${NC}"
    fi
    
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        echo -e "  SSH: ${GREEN}Running${NC}"
    else
        echo -e "  SSH: ${RED}Not Running${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Start the menu system: menu"
    echo "2. Create your first user: ssh-user-manager create testuser 7"
    echo "3. Test the connection from a client"
    echo "4. Configure monitoring alerts by editing EMAIL_ALERTS in monitor_cleanup.sh"
    echo "5. Review and adjust configuration in $INSTALL_DIR/manager.conf"
    echo ""
    echo "Installation log: $LOG_FILE"
}

# Uninstall function
uninstall() {
    log_message "${YELLOW}Uninstalling SSH User Manager...${NC}"
    
    # Stop services
    systemctl stop stunnel 2>/dev/null
    systemctl disable stunnel 2>/dev/null
    
    # Remove cron job
    "$INSTALL_DIR/monitor_cleanup.sh" remove-cron 2>/dev/null
    
    # Remove symbolic links
    rm -f /usr/local/bin/ssh-user-manager
    rm -f /usr/local/bin/ssl-cert-manager
    rm -f /usr/local/bin/ssh-monitor
    
    # Remove service file
    rm -f /etc/systemd/system/stunnel.service
    systemctl daemon-reload
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    # Restore SSH configuration
    if [[ -f /etc/ssh/sshd_config.backup ]]; then
        mv /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null
    fi
    
    log_message "${GREEN}Uninstallation completed${NC}"
    echo "Note: SSL certificates and user accounts were not removed automatically"
    echo "Manual cleanup may be required for /etc/stunnel/ and user accounts"
}

# Show usage
show_usage() {
    echo -e "${BLUE}SSH User Manager for Stunnel - Installer${NC}"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install     Install and configure the complete system"
    echo "  uninstall   Remove the system"
    echo "  verify      Verify existing installation"
    echo "  update      Update scripts (preserve configuration)"
    echo ""
    echo "This installer will:"
    echo "  - Install required dependencies (stunnel, openssh, openssl)"
    echo "  - Generate TLSv1.3 SSL certificates"
    echo "  - Configure stunnel with secure ciphers"
    echo "  - Set up SSH user management system"
    echo "  - Install monitoring and cleanup automation"
    echo "  - Configure firewall rules"
}

# Update existing installation
update() {
    log_message "${BLUE}Updating SSH User Manager...${NC}"
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_message "${RED}Installation directory not found. Please run install first.${NC}"
        exit 1
    fi
    
    # Backup existing configuration
    cp "$INSTALL_DIR/manager.conf" "/tmp/manager.conf.backup" 2>/dev/null
    
    # Copy new scripts
    copy_scripts
    
    # Restore configuration
    if [[ -f "/tmp/manager.conf.backup" ]]; then
        mv "/tmp/manager.conf.backup" "$INSTALL_DIR/manager.conf"
    fi
    
    # Restart services
    systemctl restart stunnel
    
    log_message "${GREEN}Update completed${NC}"
}

# Main function
main() {
    case "${1:-install}" in
        install)
            log_message "${BLUE}Starting SSH User Manager installation...${NC}"
            check_root
            detect_os
            install_dependencies
            create_install_dir
            copy_scripts
            create_default_config
            generate_certificates
            configure_stunnel
            configure_ssh
            configure_firewall
            create_symlinks
            install_monitoring
            
            if verify_installation; then
                show_summary
            else
                log_message "${RED}Installation completed with errors. Please check the logs.${NC}"
                exit 1
            fi
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        verify)
            verify_installation
            ;;
        update)
            check_root
            update
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"
