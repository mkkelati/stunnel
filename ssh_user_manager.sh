#!/bin/bash

# SSH User Manager for Stunnel
# Manages SSH users with limits and expiration dates
# Supports TLSv1.3 secure connections on port 443

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DB="$SCRIPT_DIR/users.db"
CONFIG_FILE="$SCRIPT_DIR/manager.conf"
LOG_FILE="/var/log/ssh_user_manager.log"
MAX_USERS=50  # Default max users
DEFAULT_EXPIRE_DAYS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # Create default config
        cat > "$CONFIG_FILE" << EOF
# SSH User Manager Configuration
MAX_USERS=$MAX_USERS
DEFAULT_EXPIRE_DAYS=$DEFAULT_EXPIRE_DAYS
ALLOW_PASSWORD_AUTH=false
REQUIRE_KEY_AUTH=true
MIN_PASSWORD_LENGTH=12
STUNNEL_PORT=443
STUNNEL_CONFIG_PATH=/etc/stunnel/stunnel.conf
EOF
        source "$CONFIG_FILE"
    fi
}

# Initialize user database
init_db() {
    if [[ ! -f "$USER_DB" ]]; then
        touch "$USER_DB"
        log_message "Initialized user database: $USER_DB"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Get current user count
get_user_count() {
    if [[ -f "$USER_DB" ]]; then
        grep -c "^[^#]" "$USER_DB" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check if user exists in database
user_exists() {
    local username="$1"
    if [[ -f "$USER_DB" ]]; then
        grep -q "^$username:" "$USER_DB"
    else
        return 1
    fi
}

# Generate secure password
generate_password() {
    local length=${1:-16}
    openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | cut -c1-$length
}

# Add user to database
add_to_db() {
    local username="$1"
    local expire_date="$2"
    local creation_date="$(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "$username:$creation_date:$expire_date:active" >> "$USER_DB"
    log_message "Added user $username to database with expiration: $expire_date"
}

# Remove user from database
remove_from_db() {
    local username="$1"
    if [[ -f "$USER_DB" ]]; then
        sed -i "/^$username:/d" "$USER_DB"
        log_message "Removed user $username from database"
    fi
}

# Create SSH user
create_user() {
    local username="$1"
    local expire_days="${2:-$DEFAULT_EXPIRE_DAYS}"
    local use_password="${3:-false}"
    
    # Validate username
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Invalid username. Use only alphanumeric characters, hyphens, and underscores.${NC}"
        return 1
    fi
    
    # Check user limits
    local current_count=$(get_user_count)
    if [[ $current_count -ge $MAX_USERS ]]; then
        echo -e "${RED}Error: Maximum user limit ($MAX_USERS) reached${NC}"
        return 1
    fi
    
    # Check if user already exists
    if user_exists "$username"; then
        echo -e "${RED}Error: User $username already exists${NC}"
        return 1
    fi
    
    # Check if system user exists
    if id "$username" &>/dev/null; then
        echo -e "${RED}Error: System user $username already exists${NC}"
        return 1
    fi
    
    # Calculate expiration date
    local expire_date
    if command -v date >/dev/null 2>&1; then
        expire_date=$(date -d "+$expire_days days" '+%Y-%m-%d')
    else
        # Fallback for systems without GNU date
        expire_date=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=$expire_days)).strftime('%Y-%m-%d'))")
    fi
    
    echo -e "${BLUE}Creating SSH user: $username${NC}"
    echo -e "${BLUE}Expiration date: $expire_date${NC}"
    
    # Create system user
    useradd -m -s /bin/bash "$username"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Failed to create system user${NC}"
        return 1
    fi
    
    # Set up SSH directory
    local ssh_dir="/home/$username/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"
    
    # Generate or set authentication
    if [[ "$use_password" == "true" ]]; then
        local password=$(generate_password $MIN_PASSWORD_LENGTH)
        echo "$username:$password" | chpasswd
        echo -e "${GREEN}User created successfully!${NC}"
        echo -e "${YELLOW}Username: $username${NC}"
        echo -e "${YELLOW}Password: $password${NC}"
        echo -e "${YELLOW}Connection: ssh $username@your_server_ip -p 443 (via stunnel)${NC}"
    else
        # Generate SSH key pair
        local key_file="$ssh_dir/id_rsa"
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "$username@stunnel-$(date +%Y%m%d)"
        
        # Set up authorized_keys
        cat "$key_file.pub" > "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown "$username:$username" "$ssh_dir/authorized_keys"
        
        # Set permissions on private key
        chmod 600 "$key_file"
        chown "$username:$username" "$key_file"
        chown "$username:$username" "$key_file.pub"
        
        echo -e "${GREEN}User created successfully!${NC}"
        echo -e "${YELLOW}Username: $username${NC}"
        echo -e "${YELLOW}Private key saved to: $key_file${NC}"
        echo -e "${YELLOW}Public key: $(cat $key_file.pub)${NC}"
        echo -e "${YELLOW}Connection: ssh -i $key_file $username@your_server_ip -p 443 (via stunnel)${NC}"
    fi
    
    # Add user to database
    add_to_db "$username" "$expire_date"
    
    # Set account expiration
    chage -E "$expire_date" "$username"
    
    echo -e "${GREEN}User $username expires on: $expire_date${NC}"
    log_message "Created user $username with expiration $expire_date"
    
    return 0
}

# Delete SSH user
delete_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Error: Username required${NC}"
        return 1
    fi
    
    # Check if user exists in our database
    if ! user_exists "$username"; then
        echo -e "${RED}Error: User $username not found in database${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Deleting user: $username${NC}"
    
    # Kill user processes
    pkill -u "$username" 2>/dev/null
    
    # Remove system user
    userdel -r "$username" 2>/dev/null
    
    # Remove from database
    remove_from_db "$username"
    
    echo -e "${GREEN}User $username deleted successfully${NC}"
    log_message "Deleted user $username"
    
    return 0
}

# List all users
list_users() {
    if [[ ! -f "$USER_DB" ]]; then
        echo -e "${YELLOW}No users found${NC}"
        return 0
    fi
    
    echo -e "${BLUE}SSH Users (via Stunnel):${NC}"
    echo "----------------------------------------"
    printf "%-15s %-20s %-12s %-8s\n" "Username" "Created" "Expires" "Status"
    echo "----------------------------------------"
    
    while IFS=':' read -r username created expires status; do
        if [[ -n "$username" && ! "$username" =~ ^# ]]; then
            # Check if user still exists on system
            if id "$username" &>/dev/null; then
                # Check if expired
                local current_date=$(date '+%Y-%m-%d')
                if [[ "$expires" < "$current_date" ]]; then
                    status="expired"
                fi
                printf "%-15s %-20s %-12s %-8s\n" "$username" "$created" "$expires" "$status"
            else
                printf "%-15s %-20s %-12s %-8s\n" "$username" "$created" "$expires" "deleted"
            fi
        fi
    done < "$USER_DB"
    
    echo "----------------------------------------"
    echo -e "${BLUE}Total users: $(get_user_count)/$MAX_USERS${NC}"
}

# Check and cleanup expired users
cleanup_expired() {
    if [[ ! -f "$USER_DB" ]]; then
        return 0
    fi
    
    local current_date=$(date '+%Y-%m-%d')
    local expired_users=()
    
    while IFS=':' read -r username created expires status; do
        if [[ -n "$username" && ! "$username" =~ ^# ]]; then
            if [[ "$expires" < "$current_date" ]]; then
                expired_users+=("$username")
            fi
        fi
    done < "$USER_DB"
    
    if [[ ${#expired_users[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Found ${#expired_users[@]} expired user(s)${NC}"
        for user in "${expired_users[@]}"; do
            echo -e "${YELLOW}Removing expired user: $user${NC}"
            delete_user "$user"
        done
    else
        echo -e "${GREEN}No expired users found${NC}"
    fi
}

# Show user details
show_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        echo -e "${RED}Error: Username required${NC}"
        return 1
    fi
    
    if ! user_exists "$username"; then
        echo -e "${RED}Error: User $username not found${NC}"
        return 1
    fi
    
    local user_info=$(grep "^$username:" "$USER_DB")
    IFS=':' read -r username created expires status <<< "$user_info"
    
    echo -e "${BLUE}User Details: $username${NC}"
    echo "----------------------------------------"
    echo "Created: $created"
    echo "Expires: $expires"
    echo "Status: $status"
    
    # Check system user
    if id "$username" &>/dev/null; then
        echo "System user: exists"
        local home_dir="/home/$username"
        if [[ -d "$home_dir/.ssh" ]]; then
            echo "SSH directory: exists"
            if [[ -f "$home_dir/.ssh/authorized_keys" ]]; then
                echo "Authorized keys: configured"
            fi
            if [[ -f "$home_dir/.ssh/id_rsa" ]]; then
                echo "Private key: available"
            fi
        fi
    else
        echo "System user: missing"
    fi
    
    echo "----------------------------------------"
}

# Show usage information
show_usage() {
    echo -e "${BLUE}SSH User Manager for Stunnel${NC}"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  create <username> [days] [--password]  Create new SSH user"
    echo "  delete <username>                      Delete SSH user"
    echo "  list                                   List all users"
    echo "  show <username>                        Show user details"
    echo "  cleanup                                Remove expired users"
    echo "  config                                 Show current configuration"
    echo "  status                                 Show system status"
    echo ""
    echo "Examples:"
    echo "  $0 create john 30                     Create user 'john' for 30 days with key auth"
    echo "  $0 create jane 7 --password            Create user 'jane' for 7 days with password"
    echo "  $0 delete john                         Delete user 'john'"
    echo "  $0 list                                List all users"
    echo ""
    echo "Configuration file: $CONFIG_FILE"
    echo "User database: $USER_DB"
    echo "Log file: $LOG_FILE"
}

# Show configuration
show_config() {
    echo -e "${BLUE}Current Configuration:${NC}"
    echo "----------------------------------------"
    echo "Max users: $MAX_USERS"
    echo "Default expire days: $DEFAULT_EXPIRE_DAYS"
    echo "Allow password auth: $ALLOW_PASSWORD_AUTH"
    echo "Require key auth: $REQUIRE_KEY_AUTH"
    echo "Min password length: $MIN_PASSWORD_LENGTH"
    echo "Stunnel port: $STUNNEL_PORT"
    echo "Config file: $CONFIG_FILE"
    echo "User database: $USER_DB"
    echo "Log file: $LOG_FILE"
    echo "----------------------------------------"
}

# Show system status
show_status() {
    echo -e "${BLUE}System Status:${NC}"
    echo "----------------------------------------"
    echo "Users: $(get_user_count)/$MAX_USERS"
    
    # Check stunnel service
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
        echo -e "Stunnel service: ${GREEN}running${NC}"
    else
        echo -e "Stunnel service: ${RED}not running${NC}"
    fi
    
    # Check SSH service
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        echo -e "SSH service: ${GREEN}running${NC}"
    else
        echo -e "SSH service: ${RED}not running${NC}"
    fi
    
    # Check port 443
    if netstat -ln 2>/dev/null | grep -q ":443 "; then
        echo -e "Port 443: ${GREEN}listening${NC}"
    else
        echo -e "Port 443: ${RED}not listening${NC}"
    fi
    
    echo "----------------------------------------"
}

# Main function
main() {
    # Initialize
    load_config
    init_db
    
    # Check if running as root for user management commands
    case "${1:-}" in
        create|delete|cleanup)
            check_root
            ;;
    esac
    
    # Parse command
    case "${1:-}" in
        create)
            local username="$2"
            local days="${3:-$DEFAULT_EXPIRE_DAYS}"
            local use_password="false"
            
            # Check for password flag
            if [[ "$4" == "--password" ]] || [[ "$3" == "--password" ]]; then
                use_password="true"
                if [[ "$3" == "--password" ]]; then
                    days="$DEFAULT_EXPIRE_DAYS"
                fi
            fi
            
            if [[ -z "$username" ]]; then
                echo -e "${RED}Error: Username required${NC}"
                show_usage
                exit 1
            fi
            
            create_user "$username" "$days" "$use_password"
            ;;
        delete)
            if [[ -z "$2" ]]; then
                echo -e "${RED}Error: Username required${NC}"
                show_usage
                exit 1
            fi
            delete_user "$2"
            ;;
        list)
            list_users
            ;;
        show)
            if [[ -z "$2" ]]; then
                echo -e "${RED}Error: Username required${NC}"
                show_usage
                exit 1
            fi
            show_user "$2"
            ;;
        cleanup)
            cleanup_expired
            ;;
        config)
            show_config
            ;;
        status)
            show_status
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"
