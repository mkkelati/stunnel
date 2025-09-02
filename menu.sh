#!/bin/bash

# SSH User Manager for Stunnel - Main Menu Interface
# Interactive menu system for managing SSH users and stunnel configuration

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/manager.conf"
INSTALL_DIR="/opt/ssh-user-manager"

# Check if installed system exists
if [[ -d "$INSTALL_DIR" ]]; then
    SCRIPT_DIR="$INSTALL_DIR"
    CONFIG_FILE="$INSTALL_DIR/manager.conf"
fi

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # Set defaults
        MAX_USERS=50
        DEFAULT_EXPIRE_DAYS=30
        STUNNEL_PORT=443
        ALLOW_PASSWORD_AUTH=true
        REQUIRE_KEY_AUTH=true
        MIN_PASSWORD_LENGTH=12
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# SSH User Manager Configuration
MAX_USERS=$MAX_USERS
DEFAULT_EXPIRE_DAYS=$DEFAULT_EXPIRE_DAYS
ALLOW_PASSWORD_AUTH=$ALLOW_PASSWORD_AUTH
REQUIRE_KEY_AUTH=$REQUIRE_KEY_AUTH
MIN_PASSWORD_LENGTH=$MIN_PASSWORD_LENGTH
STUNNEL_PORT=$STUNNEL_PORT
STUNNEL_CONFIG_PATH=/etc/stunnel/stunnel.conf
EOF
}

# Display header
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               SSH User Manager for Stunnel                    ║${NC}"
    echo -e "${CYAN}║              TLSv1.3 Secure Tunnel Manager                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Current Configuration:${NC}"
    echo -e "  Max Users: ${YELLOW}$MAX_USERS${NC}"
    echo -e "  Default Expiry: ${YELLOW}$DEFAULT_EXPIRE_DAYS days${NC}"
    echo -e "  Stunnel Port: ${YELLOW}$STUNNEL_PORT${NC}"
    
    # Show system status
    local stunnel_status="❌ Stopped"
    local ssh_status="❌ Stopped"
    local port_status="❌ Not Listening"
    
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
        stunnel_status="✅ Running"
    fi
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        ssh_status="✅ Running"
    fi
    
    if netstat -ln 2>/dev/null | grep -q ":$STUNNEL_PORT "; then
        port_status="✅ Listening"
    fi
    
    echo -e "  Stunnel: $stunnel_status"
    echo -e "  SSH: $ssh_status"
    echo -e "  Port $STUNNEL_PORT: $port_status"
    
    # Show user count
    local user_count=0
    if [[ -f "$SCRIPT_DIR/users.db" ]]; then
        user_count=$(grep -c "^[^#]" "$SCRIPT_DIR/users.db" 2>/dev/null || echo "0")
    fi
    echo -e "  Active Users: ${YELLOW}$user_count/$MAX_USERS${NC}"
    echo ""
}

# Main menu
show_main_menu() {
    echo -e "${WHITE}Main Menu:${NC}"
    echo -e "${GREEN}1.${NC} Create User"
    echo -e "${GREEN}2.${NC} Delete User"  
    echo -e "${GREEN}3.${NC} List Users"
    echo -e "${GREEN}4.${NC} User Limits & Settings"
    echo -e "${GREEN}5.${NC} Stunnel Configuration"
    echo -e "${GREEN}6.${NC} System Status & Monitoring"
    echo -e "${GREEN}7.${NC} SSL Certificate Management"
    echo -e "${GREEN}8.${NC} Connection Information"
    echo -e "${GREEN}9.${NC} System Installation/Update"
    echo -e "${RED}0.${NC} Exit"
    echo ""
    echo -n -e "${CYAN}Please select an option [0-9]: ${NC}"
}

# Create user menu
create_user_menu() {
    clear
    show_header
    echo -e "${WHITE}Create New User${NC}"
    echo "─────────────────"
    echo ""
    
    read -p "Enter username: " username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Username cannot be empty${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter expiry days [$DEFAULT_EXPIRE_DAYS]: " days
    days=${days:-$DEFAULT_EXPIRE_DAYS}
    
    echo ""
    echo "Authentication method:"
    echo "1. SSH Key (Recommended)"
    echo "2. Password"
    read -p "Choose method [1-2]: " auth_method
    
    local password_flag=""
    if [[ "$auth_method" == "2" ]]; then
        password_flag="--password"
    fi
    
    echo ""
    echo -e "${BLUE}Creating user: $username${NC}"
    echo -e "${BLUE}Expiry: $days days${NC}"
    echo -e "${BLUE}Auth: $([ "$auth_method" == "2" ] && echo "Password" || echo "SSH Key")${NC}"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/ssh_user_manager.sh" ]]; then
        "$SCRIPT_DIR/ssh_user_manager.sh" create "$username" "$days" $password_flag
    elif command -v ssh-user-manager >/dev/null 2>&1; then
        ssh-user-manager create "$username" "$days" $password_flag
    else
        echo -e "${RED}SSH User Manager not found. Please install the system first.${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Delete user menu
delete_user_menu() {
    clear
    show_header
    echo -e "${WHITE}Delete User${NC}"
    echo "─────────────"
    echo ""
    
    # Show current users first
    if [[ -f "$SCRIPT_DIR/users.db" ]]; then
        echo -e "${BLUE}Current users:${NC}"
        while IFS=':' read -r username created expires status; do
            if [[ -n "$username" && ! "$username" =~ ^# ]]; then
                echo "  - $username (expires: $expires)"
            fi
        done < "$SCRIPT_DIR/users.db"
        echo ""
    fi
    
    read -p "Enter username to delete: " username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Username cannot be empty${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Warning: This will permanently delete user '$username'${NC}"
    read -p "Are you sure? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [[ -x "$SCRIPT_DIR/ssh_user_manager.sh" ]]; then
            "$SCRIPT_DIR/ssh_user_manager.sh" delete "$username"
        elif command -v ssh-user-manager >/dev/null 2>&1; then
            ssh-user-manager delete "$username"
        else
            echo -e "${RED}SSH User Manager not found. Please install the system first.${NC}"
        fi
    else
        echo -e "${BLUE}Deletion cancelled${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# List users
list_users_menu() {
    clear
    show_header
    echo -e "${WHITE}User List${NC}"
    echo "──────────"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/ssh_user_manager.sh" ]]; then
        "$SCRIPT_DIR/ssh_user_manager.sh" list
    elif command -v ssh-user-manager >/dev/null 2>&1; then
        ssh-user-manager list
    else
        echo -e "${RED}SSH User Manager not found. Please install the system first.${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# User limits and settings
user_limits_menu() {
    clear
    show_header
    echo -e "${WHITE}User Limits & Settings${NC}"
    echo "──────────────────────"
    echo ""
    echo -e "Current Settings:"
    echo -e "  Max Users: ${YELLOW}$MAX_USERS${NC}"
    echo -e "  Default Expiry: ${YELLOW}$DEFAULT_EXPIRE_DAYS days${NC}"
    echo -e "  Password Auth: ${YELLOW}$ALLOW_PASSWORD_AUTH${NC}"
    echo -e "  Key Auth Required: ${YELLOW}$REQUIRE_KEY_AUTH${NC}"
    echo -e "  Min Password Length: ${YELLOW}$MIN_PASSWORD_LENGTH${NC}"
    echo ""
    echo "Options:"
    echo "1. Change Maximum Users"
    echo "2. Change Default Expiry Days"
    echo "3. Toggle Password Authentication"
    echo "4. Change Minimum Password Length"
    echo "5. Cleanup Expired Users"
    echo "6. Back to Main Menu"
    echo ""
    read -p "Select option [1-6]: " option
    
    case $option in
        1)
            read -p "Enter new max users [$MAX_USERS]: " new_max
            if [[ "$new_max" =~ ^[0-9]+$ ]] && [[ $new_max -gt 0 ]]; then
                MAX_USERS=$new_max
                save_config
                echo -e "${GREEN}Max users updated to $MAX_USERS${NC}"
            else
                echo -e "${RED}Invalid number${NC}"
            fi
            ;;
        2)
            read -p "Enter new default expiry days [$DEFAULT_EXPIRE_DAYS]: " new_days
            if [[ "$new_days" =~ ^[0-9]+$ ]] && [[ $new_days -gt 0 ]]; then
                DEFAULT_EXPIRE_DAYS=$new_days
                save_config
                echo -e "${GREEN}Default expiry updated to $DEFAULT_EXPIRE_DAYS days${NC}"
            else
                echo -e "${RED}Invalid number${NC}"
            fi
            ;;
        3)
            if [[ "$ALLOW_PASSWORD_AUTH" == "true" ]]; then
                ALLOW_PASSWORD_AUTH="false"
                echo -e "${GREEN}Password authentication disabled${NC}"
            else
                ALLOW_PASSWORD_AUTH="true"
                echo -e "${GREEN}Password authentication enabled${NC}"
            fi
            save_config
            ;;
        4)
            read -p "Enter minimum password length [$MIN_PASSWORD_LENGTH]: " new_length
            if [[ "$new_length" =~ ^[0-9]+$ ]] && [[ $new_length -ge 8 ]]; then
                MIN_PASSWORD_LENGTH=$new_length
                save_config
                echo -e "${GREEN}Minimum password length updated to $MIN_PASSWORD_LENGTH${NC}"
            else
                echo -e "${RED}Invalid length (minimum 8)${NC}"
            fi
            ;;
        5)
            echo -e "${BLUE}Running cleanup of expired users...${NC}"
            if [[ -x "$SCRIPT_DIR/ssh_user_manager.sh" ]]; then
                "$SCRIPT_DIR/ssh_user_manager.sh" cleanup
            elif command -v ssh-user-manager >/dev/null 2>&1; then
                ssh-user-manager cleanup
            else
                echo -e "${RED}SSH User Manager not found${NC}"
            fi
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    if [[ $option != 6 ]]; then
        echo ""
        read -p "Press Enter to continue..."
        user_limits_menu
    fi
}

# Stunnel configuration menu
stunnel_config_menu() {
    clear
    show_header
    echo -e "${WHITE}Stunnel Configuration${NC}"
    echo "─────────────────────"
    echo ""
    echo -e "Current Port: ${YELLOW}$STUNNEL_PORT${NC}"
    
    # Check if stunnel is running
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
        echo -e "Status: ${GREEN}✅ Running${NC}"
    else
        echo -e "Status: ${RED}❌ Stopped${NC}"
    fi
    
    echo ""
    echo "Options:"
    echo "1. Change Stunnel Port"
    echo "2. Start Stunnel Service"
    echo "3. Stop Stunnel Service" 
    echo "4. Restart Stunnel Service"
    echo "5. View Stunnel Configuration"
    echo "6. Test Stunnel Configuration"
    echo "7. View Stunnel Logs"
    echo "8. Back to Main Menu"
    echo ""
    read -p "Select option [1-8]: " option
    
    case $option in
        1)
            read -p "Enter new port [$STUNNEL_PORT]: " new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ $new_port -ge 1 ]] && [[ $new_port -le 65535 ]]; then
                if [[ $new_port -eq 22 ]]; then
                    echo -e "${RED}Cannot use port 22 (SSH port)${NC}"
                elif netstat -ln 2>/dev/null | grep -q ":$new_port "; then
                    echo -e "${RED}Port $new_port is already in use${NC}"
                else
                    STUNNEL_PORT=$new_port
                    save_config
                    
                    # Update stunnel configuration
                    if [[ -f "/etc/stunnel/stunnel.conf" ]]; then
                        sed -i "s/accept = [0-9]*/accept = $STUNNEL_PORT/" /etc/stunnel/stunnel.conf
                        echo -e "${GREEN}Stunnel port updated to $STUNNEL_PORT${NC}"
                        echo -e "${YELLOW}Restart stunnel service to apply changes${NC}"
                    else
                        echo -e "${YELLOW}Stunnel configuration file not found${NC}"
                    fi
                fi
            else
                echo -e "${RED}Invalid port number (1-65535)${NC}"
            fi
            ;;
        2)
            systemctl start stunnel4 2>/dev/null || systemctl start stunnel 2>/dev/null
            if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
                echo -e "${GREEN}Stunnel service started${NC}"
            else
                echo -e "${RED}Failed to start stunnel service${NC}"
            fi
            ;;
        3)
            systemctl stop stunnel4 2>/dev/null || systemctl stop stunnel 2>/dev/null
            echo -e "${YELLOW}Stunnel service stopped${NC}"
            ;;
        4)
            systemctl restart stunnel4 2>/dev/null || systemctl restart stunnel 2>/dev/null
            if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
                echo -e "${GREEN}Stunnel service restarted${NC}"
            else
                echo -e "${RED}Failed to restart stunnel service${NC}"
            fi
            ;;
        5)
            if [[ -f "/etc/stunnel/stunnel.conf" ]]; then
                echo -e "${BLUE}Stunnel Configuration:${NC}"
                echo "─────────────────────"
                cat /etc/stunnel/stunnel.conf
            else
                echo -e "${RED}Stunnel configuration file not found${NC}"
            fi
            ;;
        6)
            if command -v stunnel >/dev/null 2>&1; then
                echo -e "${BLUE}Testing stunnel configuration...${NC}"
                stunnel -test /etc/stunnel/stunnel.conf
            else
                echo -e "${RED}Stunnel command not found${NC}"
            fi
            ;;
        7)
            if [[ -f "/var/log/stunnel/stunnel.log" ]]; then
                echo -e "${BLUE}Recent Stunnel Logs:${NC}"
                echo "───────────────────"
                tail -20 /var/log/stunnel/stunnel.log
            else
                echo -e "${YELLOW}Stunnel log file not found${NC}"
            fi
            ;;
        8)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    if [[ $option != 8 ]]; then
        echo ""
        read -p "Press Enter to continue..."
        stunnel_config_menu
    fi
}

# System status and monitoring
system_status_menu() {
    clear
    show_header
    echo -e "${WHITE}System Status & Monitoring${NC}"
    echo "─────────────────────────"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/monitor_cleanup.sh" ]]; then
        "$SCRIPT_DIR/monitor_cleanup.sh" status
    elif command -v ssh-monitor >/dev/null 2>&1; then
        ssh-monitor status
    else
        echo -e "${RED}Monitor script not found${NC}"
    fi
    
    echo ""
    echo "Options:"
    echo "1. View Active Sessions"
    echo "2. Check System Health"
    echo "3. Run Full Monitor Cycle"
    echo "4. Generate Usage Report"
    echo "5. View Logs"
    echo "6. Back to Main Menu"
    echo ""
    read -p "Select option [1-6]: " option
    
    case $option in
        1)
            echo -e "${BLUE}Active SSH Sessions:${NC}"
            who
            ;;
        2)
            if [[ -x "$SCRIPT_DIR/monitor_cleanup.sh" ]]; then
                "$SCRIPT_DIR/monitor_cleanup.sh" health
            elif command -v ssh-monitor >/dev/null 2>&1; then
                ssh-monitor health
            fi
            ;;
        3)
            if [[ -x "$SCRIPT_DIR/monitor_cleanup.sh" ]]; then
                "$SCRIPT_DIR/monitor_cleanup.sh" monitor
            elif command -v ssh-monitor >/dev/null 2>&1; then
                ssh-monitor monitor
            fi
            ;;
        4)
            if [[ -x "$SCRIPT_DIR/monitor_cleanup.sh" ]]; then
                "$SCRIPT_DIR/monitor_cleanup.sh" report
            elif command -v ssh-monitor >/dev/null 2>&1; then
                ssh-monitor report
            fi
            ;;
        5)
            echo -e "${BLUE}Recent System Logs:${NC}"
            echo "─────────────────"
            for log in /var/log/ssh_user_manager*.log; do
                if [[ -f "$log" ]]; then
                    echo "=== $(basename "$log") ==="
                    tail -10 "$log"
                    echo ""
                fi
            done
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    if [[ $option != 6 ]]; then
        echo ""
        read -p "Press Enter to continue..."
        system_status_menu
    fi
}

# SSL certificate management
ssl_cert_menu() {
    clear
    show_header
    echo -e "${WHITE}SSL Certificate Management${NC}"
    echo "─────────────────────────"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/generate_ssl_cert.sh" ]]; then
        "$SCRIPT_DIR/generate_ssl_cert.sh" status
    elif command -v ssl-cert-manager >/dev/null 2>&1; then
        ssl-cert-manager status
    else
        echo -e "${RED}SSL certificate manager not found${NC}"
    fi
    
    echo ""
    echo "Options:"
    echo "1. Generate New Certificate"
    echo "2. View Certificate Information"
    echo "3. Verify Certificate"
    echo "4. Back to Main Menu"
    echo ""
    read -p "Select option [1-4]: " option
    
    case $option in
        1)
            if [[ -x "$SCRIPT_DIR/generate_ssl_cert.sh" ]]; then
                "$SCRIPT_DIR/generate_ssl_cert.sh" generate
            elif command -v ssl-cert-manager >/dev/null 2>&1; then
                ssl-cert-manager generate
            fi
            ;;
        2)
            if [[ -x "$SCRIPT_DIR/generate_ssl_cert.sh" ]]; then
                "$SCRIPT_DIR/generate_ssl_cert.sh" info
            elif command -v ssl-cert-manager >/dev/null 2>&1; then
                ssl-cert-manager info
            fi
            ;;
        3)
            if [[ -x "$SCRIPT_DIR/generate_ssl_cert.sh" ]]; then
                "$SCRIPT_DIR/generate_ssl_cert.sh" verify
            elif command -v ssl-cert-manager >/dev/null 2>&1; then
                ssl-cert-manager verify
            fi
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    if [[ $option != 4 ]]; then
        echo ""
        read -p "Press Enter to continue..."
        ssl_cert_menu
    fi
}

# Connection information
connection_info_menu() {
    clear
    show_header
    echo -e "${WHITE}Connection Information${NC}"
    echo "──────────────────────"
    echo ""
    
    # Get server IP
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo -e "${BLUE}Server Connection Details:${NC}"
    echo "─────────────────────────"
    echo -e "Server IP: ${YELLOW}$server_ip${NC}"
    echo -e "Port: ${YELLOW}$STUNNEL_PORT${NC}"
    echo -e "Protocol: ${YELLOW}SSL/TLS proxy - SSH${NC}"
    echo -e "Encryption: ${YELLOW}TLSv1.3 with TLS_AES_256_GCM_SHA384${NC}"
    echo ""
    
    echo -e "${BLUE}HTTP Injector Configuration:${NC}"
    echo "───────────────────────────"
    echo "Server Type: SSH"
    echo "Protocol: SSL/TLS proxy"
    echo "Server Address: $server_ip"
    echo "Port: $STUNNEL_PORT"
    echo "Username: [your created username]"
    echo "Authentication: SSH Key or Password"
    echo ""
    
    echo -e "${BLUE}Command Line Connection:${NC}"
    echo "──────────────────────────"
    echo "ssh username@$server_ip -p $STUNNEL_PORT"
    echo ""
    
    echo -e "${BLUE}SSH Key Connection:${NC}"
    echo "─────────────────────"
    echo "ssh -i /path/to/private/key username@$server_ip -p $STUNNEL_PORT"
    echo ""
    
    if [[ -f "$SCRIPT_DIR/users.db" ]]; then
        echo -e "${BLUE}Available Users:${NC}"
        echo "───────────────"
        while IFS=':' read -r username created expires status; do
            if [[ -n "$username" && ! "$username" =~ ^# ]]; then
                local current_date=$(date '+%Y-%m-%d')
                if [[ "$expires" > "$current_date" ]]; then
                    echo -e "  ✅ $username (expires: $expires)"
                else
                    echo -e "  ❌ $username (expired: $expires)"
                fi
            fi
        done < "$SCRIPT_DIR/users.db"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Installation and update menu
installation_menu() {
    clear
    show_header
    echo -e "${WHITE}System Installation/Update${NC}"
    echo "─────────────────────────"
    echo ""
    
    if [[ -d "/opt/ssh-user-manager" ]]; then
        echo -e "Installation Status: ${GREEN}✅ Installed${NC}"
        echo -e "Installation Path: ${YELLOW}/opt/ssh-user-manager${NC}"
    else
        echo -e "Installation Status: ${RED}❌ Not Installed${NC}"
    fi
    
    echo ""
    echo "Options:"
    echo "1. Install System"
    echo "2. Update System"
    echo "3. Uninstall System"
    echo "4. Verify Installation"
    echo "5. View Installation Logs"
    echo "6. Back to Main Menu"
    echo ""
    read -p "Select option [1-6]: " option
    
    case $option in
        1)
            if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
                echo -e "${BLUE}Starting system installation...${NC}"
                "$SCRIPT_DIR/install.sh" install
            else
                echo -e "${RED}Installation script not found${NC}"
            fi
            ;;
        2)
            if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
                echo -e "${BLUE}Updating system...${NC}"
                "$SCRIPT_DIR/install.sh" update
            else
                echo -e "${RED}Installation script not found${NC}"
            fi
            ;;
        3)
            echo -e "${YELLOW}Warning: This will completely remove the SSH User Manager system${NC}"
            read -p "Are you sure? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
                    "$SCRIPT_DIR/install.sh" uninstall
                else
                    echo -e "${RED}Installation script not found${NC}"
                fi
            fi
            ;;
        4)
            if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
                "$SCRIPT_DIR/install.sh" verify
            else
                echo -e "${RED}Installation script not found${NC}"
            fi
            ;;
        5)
            if [[ -f "/var/log/ssh_user_manager_install.log" ]]; then
                echo -e "${BLUE}Installation Logs:${NC}"
                echo "─────────────────"
                tail -30 /var/log/ssh_user_manager_install.log
            else
                echo -e "${YELLOW}Installation log not found${NC}"
            fi
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    if [[ $option != 6 ]]; then
        echo ""
        read -p "Press Enter to continue..."
        installation_menu
    fi
}

# Main program loop
main() {
    # Load configuration
    load_config
    
    while true; do
        show_header
        show_main_menu
        
        read choice
        echo ""
        
        case $choice in
            1)
                create_user_menu
                ;;
            2)
                delete_user_menu
                ;;
            3)
                list_users_menu
                ;;
            4)
                user_limits_menu
                ;;
            5)
                stunnel_config_menu
                ;;
            6)
                system_status_menu
                ;;
            7)
                ssl_cert_menu
                ;;
            8)
                connection_info_menu
                ;;
            9)
                installation_menu
                ;;
            0)
                echo -e "${GREEN}Thank you for using SSH User Manager for Stunnel!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Check if running as root for certain operations
check_root_warning() {
    if [[ $EUID -ne 0 ]] && [[ "$1" =~ ^(1|2|4|5|7|9)$ ]]; then
        echo -e "${YELLOW}Note: Some operations may require root privileges${NC}"
        echo ""
    fi
}

# Run main program
main "$@"
