#!/bin/bash

# Monitoring and Cleanup Script for SSH User Manager
# Automatically monitors and cleans up expired users
# Can be run as a cron job for automated maintenance

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_MANAGER="$SCRIPT_DIR/ssh_user_manager.sh"
LOG_FILE="/var/log/ssh_user_monitor.log"
LOCK_FILE="/var/run/ssh_user_monitor.lock"
EMAIL_ALERTS=false
ADMIN_EMAIL="admin@example.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    echo -e "$message"
}

# Check if script is already running
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_message "${YELLOW}Monitor script is already running (PID: $pid)${NC}"
            exit 1
        else
            log_message "${YELLOW}Removing stale lock file${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    
    # Remove lock file on exit
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# Send email notification
send_email() {
    local subject="$1"
    local body="$2"
    
    if [[ "$EMAIL_ALERTS" == "true" ]] && command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$ADMIN_EMAIL"
        log_message "${GREEN}Email notification sent to $ADMIN_EMAIL${NC}"
    fi
}

# Check system health
check_system_health() {
    local issues=()
    
    # Check stunnel service
    if ! systemctl is-active --quiet stunnel4 2>/dev/null && ! systemctl is-active --quiet stunnel 2>/dev/null; then
        issues+=("Stunnel service is not running")
    fi
    
    # Check SSH service
    if ! systemctl is-active --quiet ssh 2>/dev/null && ! systemctl is-active --quiet sshd 2>/dev/null; then
        issues+=("SSH service is not running")
    fi
    
    # Check port 443
    if ! netstat -ln 2>/dev/null | grep -q ":443 "; then
        issues+=("Port 443 is not listening")
    fi
    
    # Check certificate expiration
    local cert_file="/etc/stunnel/stunnel.pem"
    if [[ -f "$cert_file" ]]; then
        if ! openssl x509 -in "$cert_file" -noout -checkend 2592000 >/dev/null 2>&1; then
            issues+=("SSL certificate expires within 30 days")
        fi
    else
        issues+=("SSL certificate not found")
    fi
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        issues+=("Disk usage is above 90% ($disk_usage%)")
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $mem_usage -gt 90 ]]; then
        issues+=("Memory usage is above 90% ($mem_usage%)")
    fi
    
    # Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_message "${RED}System health issues detected:${NC}"
        local issue_list=""
        for issue in "${issues[@]}"; do
            log_message "${RED}  - $issue${NC}"
            issue_list="$issue_list- $issue\n"
        done
        
        send_email "SSH User Manager - System Health Alert" "The following issues were detected:\n\n$issue_list"
        return 1
    else
        log_message "${GREEN}System health check passed${NC}"
        return 0
    fi
}

# Monitor user sessions
monitor_sessions() {
    local active_users=()
    local session_count=0
    
    # Get active SSH sessions
    while read -r user; do
        if [[ -n "$user" && "$user" != "root" ]]; then
            active_users+=("$user")
            ((session_count++))
        fi
    done < <(who | awk '{print $1}' | sort -u)
    
    log_message "${BLUE}Active SSH sessions: $session_count${NC}"
    
    if [[ ${#active_users[@]} -gt 0 ]]; then
        for user in "${active_users[@]}"; do
            log_message "${BLUE}  - $user${NC}"
        done
    fi
    
    # Check for suspicious activity (multiple sessions from same user)
    local suspicious_users=$(who | awk '{print $1}' | sort | uniq -c | awk '$1 > 3 {print $2}')
    if [[ -n "$suspicious_users" ]]; then
        log_message "${YELLOW}Users with multiple sessions detected:${NC}"
        echo "$suspicious_users" | while read -r user; do
            local count=$(who | grep -c "^$user ")
            log_message "${YELLOW}  - $user: $count sessions${NC}"
        done
        
        send_email "SSH User Manager - Suspicious Activity" "Multiple sessions detected for users:\n$suspicious_users"
    fi
}

# Check for users near expiration
check_expiring_users() {
    local expiring_users=()
    local user_db="$SCRIPT_DIR/users.db"
    
    if [[ ! -f "$user_db" ]]; then
        return 0
    fi
    
    local current_date=$(date '+%Y-%m-%d')
    local warning_date=$(date -d "+7 days" '+%Y-%m-%d')
    
    while IFS=':' read -r username created expires status; do
        if [[ -n "$username" && ! "$username" =~ ^# ]]; then
            if [[ "$expires" > "$current_date" && "$expires" <= "$warning_date" ]]; then
                expiring_users+=("$username:$expires")
            fi
        fi
    done < "$user_db"
    
    if [[ ${#expiring_users[@]} -gt 0 ]]; then
        log_message "${YELLOW}Users expiring within 7 days:${NC}"
        local expiry_list=""
        for user_info in "${expiring_users[@]}"; do
            IFS=':' read -r username expires <<< "$user_info"
            log_message "${YELLOW}  - $username expires on $expires${NC}"
            expiry_list="$expiry_list- $username expires on $expires\n"
        done
        
        send_email "SSH User Manager - User Expiration Warning" "The following users will expire within 7 days:\n\n$expiry_list"
    fi
}

# Cleanup expired users
cleanup_expired_users() {
    log_message "${BLUE}Running expired user cleanup...${NC}"
    
    if [[ -x "$USER_MANAGER" ]]; then
        local cleanup_output=$("$USER_MANAGER" cleanup 2>&1)
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            log_message "${GREEN}Expired user cleanup completed${NC}"
            if [[ "$cleanup_output" =~ "Removing expired user:" ]]; then
                log_message "$cleanup_output"
                send_email "SSH User Manager - Expired Users Removed" "Expired users have been automatically removed:\n\n$cleanup_output"
            fi
        else
            log_message "${RED}Expired user cleanup failed${NC}"
            log_message "$cleanup_output"
            send_email "SSH User Manager - Cleanup Failed" "Expired user cleanup failed:\n\n$cleanup_output"
        fi
    else
        log_message "${RED}User manager script not found or not executable: $USER_MANAGER${NC}"
    fi
}

# Generate usage report
generate_report() {
    local report_file="/tmp/ssh_user_report_$(date +%Y%m%d).txt"
    local user_db="$SCRIPT_DIR/users.db"
    
    {
        echo "SSH User Manager Report - $(date)"
        echo "======================================"
        echo ""
        
        # System status
        echo "System Status:"
        echo "--------------"
        if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
            echo "Stunnel: Running"
        else
            echo "Stunnel: Not Running"
        fi
        
        if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
            echo "SSH: Running"
        else
            echo "SSH: Not Running"
        fi
        echo ""
        
        # User statistics
        if [[ -f "$user_db" ]]; then
            local total_users=$(grep -c "^[^#]" "$user_db" 2>/dev/null || echo "0")
            local active_users=0
            local expired_users=0
            local current_date=$(date '+%Y-%m-%d')
            
            while IFS=':' read -r username created expires status; do
                if [[ -n "$username" && ! "$username" =~ ^# ]]; then
                    if [[ "$expires" > "$current_date" ]]; then
                        ((active_users++))
                    else
                        ((expired_users++))
                    fi
                fi
            done < "$user_db"
            
            echo "User Statistics:"
            echo "----------------"
            echo "Total Users: $total_users"
            echo "Active Users: $active_users"
            echo "Expired Users: $expired_users"
            echo ""
            
            # List active users
            if [[ $active_users -gt 0 ]]; then
                echo "Active Users:"
                echo "-------------"
                while IFS=':' read -r username created expires status; do
                    if [[ -n "$username" && ! "$username" =~ ^# && "$expires" > "$current_date" ]]; then
                        echo "$username (expires: $expires)"
                    fi
                done < "$user_db"
            fi
        else
            echo "No user database found"
        fi
        
        echo ""
        echo "Report generated: $(date)"
        
    } > "$report_file"
    
    log_message "${GREEN}Usage report generated: $report_file${NC}"
    
    # Email report if configured
    if [[ "$EMAIL_ALERTS" == "true" ]]; then
        send_email "SSH User Manager - Daily Report" "$(cat $report_file)"
    fi
}

# Monitor log file size
monitor_logs() {
    local max_log_size=10485760  # 10MB in bytes
    
    for log in "$LOG_FILE" "/var/log/stunnel/stunnel.log" "/var/log/ssh_user_manager.log"; do
        if [[ -f "$log" ]]; then
            local log_size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo "0")
            if [[ $log_size -gt $max_log_size ]]; then
                log_message "${YELLOW}Log file $log is large ($(($log_size / 1024 / 1024))MB), rotating...${NC}"
                
                # Rotate log
                mv "$log" "$log.old"
                touch "$log"
                
                # Keep only last 5 rotated logs
                find "$(dirname "$log")" -name "$(basename "$log").old*" -mtime +5 -delete 2>/dev/null
            fi
        fi
    done
}

# Full monitoring run
full_monitor() {
    log_message "${BLUE}Starting SSH User Manager monitoring cycle${NC}"
    
    # System health check
    check_system_health
    
    # Monitor active sessions
    monitor_sessions
    
    # Check for expiring users
    check_expiring_users
    
    # Cleanup expired users
    cleanup_expired_users
    
    # Monitor log sizes
    monitor_logs
    
    log_message "${GREEN}Monitoring cycle completed${NC}"
}

# Quick status check
quick_status() {
    echo -e "${BLUE}SSH User Manager Quick Status${NC}"
    echo "================================"
    
    # Service status
    if systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null; then
        echo -e "Stunnel: ${GREEN}Running${NC}"
    else
        echo -e "Stunnel: ${RED}Not Running${NC}"
    fi
    
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        echo -e "SSH: ${GREEN}Running${NC}"
    else
        echo -e "SSH: ${RED}Not Running${NC}"
    fi
    
    # Port status
    if netstat -ln 2>/dev/null | grep -q ":443 "; then
        echo -e "Port 443: ${GREEN}Listening${NC}"
    else
        echo -e "Port 443: ${RED}Not Listening${NC}"
    fi
    
    # User count
    local user_db="$SCRIPT_DIR/users.db"
    if [[ -f "$user_db" ]]; then
        local user_count=$(grep -c "^[^#]" "$user_db" 2>/dev/null || echo "0")
        echo "Users: $user_count"
    else
        echo "Users: 0"
    fi
    
    # Active sessions
    local session_count=$(who | wc -l)
    echo "Active sessions: $session_count"
    
    echo "================================"
}

# Install cron job
install_cron() {
    local cron_schedule="${1:-0 */6 * * *}"  # Every 6 hours by default
    local script_path="$(readlink -f "$0")"
    
    echo -e "${BLUE}Installing cron job for automated monitoring${NC}"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$script_path monitor"; then
        echo -e "${YELLOW}Cron job already exists${NC}"
        return 0
    fi
    
    # Add cron job
    (crontab -l 2>/dev/null; echo "$cron_schedule $script_path monitor >/dev/null 2>&1") | crontab -
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Cron job installed successfully${NC}"
        echo "Schedule: $cron_schedule"
        echo "Command: $script_path monitor"
    else
        echo -e "${RED}Failed to install cron job${NC}"
        return 1
    fi
}

# Remove cron job
remove_cron() {
    local script_path="$(readlink -f "$0")"
    
    echo -e "${BLUE}Removing cron job for automated monitoring${NC}"
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "$script_path monitor" | crontab -
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Cron job removed successfully${NC}"
    else
        echo -e "${RED}Failed to remove cron job${NC}"
        return 1
    fi
}

# Show usage
show_usage() {
    echo -e "${BLUE}SSH User Manager Monitor${NC}"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  monitor             Run full monitoring cycle"
    echo "  status              Show quick status"
    echo "  cleanup             Cleanup expired users only"
    echo "  health              Check system health"
    echo "  sessions            Monitor active sessions"
    echo "  expiring            Check for expiring users"
    echo "  report              Generate usage report"
    echo "  install-cron [schedule]  Install cron job (default: every 6 hours)"
    echo "  remove-cron         Remove cron job"
    echo ""
    echo "Examples:"
    echo "  $0 monitor                  # Run full monitoring"
    echo "  $0 status                   # Quick status check"
    echo "  $0 install-cron '0 */4 * * *'  # Monitor every 4 hours"
    echo ""
    echo "Configuration:"
    echo "  Edit EMAIL_ALERTS and ADMIN_EMAIL variables in this script"
    echo "  Log file: $LOG_FILE"
}

# Main function
main() {
    case "${1:-monitor}" in
        monitor)
            check_lock
            full_monitor
            ;;
        status)
            quick_status
            ;;
        cleanup)
            check_lock
            cleanup_expired_users
            ;;
        health)
            check_system_health
            ;;
        sessions)
            monitor_sessions
            ;;
        expiring)
            check_expiring_users
            ;;
        report)
            generate_report
            ;;
        install-cron)
            install_cron "$2"
            ;;
        remove-cron)
            remove_cron
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"
