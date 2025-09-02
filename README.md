# SSH User Manager for Stunnel

A comprehensive SSH user management system with secure TLSv1.3 tunneling through stunnel on port 443. This system provides automated user creation, management, expiration handling, and monitoring with enterprise-grade security features.

## Features

- 🔐 **TLSv1.3 Security**: Uses TLS_AES_256_GCM_SHA384 cipher for maximum security
- 👥 **User Management**: Create, delete, and manage SSH users with limits
- ⏰ **Expiration Control**: Automatic user expiration and cleanup
- 📊 **Monitoring**: Real-time monitoring and alerting system
- 🔧 **Automated Setup**: One-click installation and configuration
- 🛡️ **Security**: Port 443 tunneling, key-based authentication
- 📧 **Notifications**: Email alerts for system events
- 🔄 **Automation**: Cron-based cleanup and monitoring

## Quick Start

### 1. Installation

```bash
# Clone or download the files
chmod +x install.sh
sudo ./install.sh install
```

### 2. Start the Menu System

```bash
# Launch interactive menu (recommended for beginners)
menu

# Or use command line directly
sudo ssh-user-manager create john 30
sudo ssh-user-manager create jane 7 --password
```

### 3. Connect from Client

```bash
# Using SSH key
ssh -i /path/to/private/key john@your-server-ip -p 443

# Using password
ssh jane@your-server-ip -p 443
```

## System Architecture

```
Client → Port 443 (TLSv1.3/stunnel) → SSH Server (Port 22)
```

- **Port 443**: SSL/TLS tunnel endpoint (stunnel)
- **TLSv1.3**: Latest TLS version with AES-256-GCM encryption
- **SSH Server**: Local SSH daemon on port 22
- **User Database**: Local database tracking users and expiration

## Configuration

### Stunnel Configuration (`stunnel.conf`)
- **Protocol**: TLSv1.3 only
- **Cipher**: TLS_AES_256_GCM_SHA384
- **Port**: 443 (default for HTTPS compatibility)
- **Target**: Local SSH server (127.0.0.1:22)

### User Manager Configuration (`manager.conf`)
```bash
MAX_USERS=50                    # Maximum number of users
DEFAULT_EXPIRE_DAYS=30          # Default expiration in days
ALLOW_PASSWORD_AUTH=true        # Allow password authentication
REQUIRE_KEY_AUTH=true           # Require SSH key authentication
MIN_PASSWORD_LENGTH=12          # Minimum password length
STUNNEL_PORT=443                # Stunnel listening port (configurable)
```

**Note**: The stunnel port can be changed through the menu system (option 5) or by editing the configuration file. Default is 443 for HTTP Injector compatibility.

## Commands Reference

### Interactive Menu System

```bash
# Start the main menu (easiest way to manage the system)
menu
```

The menu provides:
- User creation and deletion
- User limits and settings management  
- Stunnel configuration (including port changes)
- System monitoring and status
- SSL certificate management
- Connection information display
- Installation and updates

### Command Line Interface

```bash
# Create new user
ssh-user-manager create <username> [days] [--password]

# Delete user
ssh-user-manager delete <username>

# List all users
ssh-user-manager list

# Show user details
ssh-user-manager show <username>

# Clean up expired users
ssh-user-manager cleanup

# Show system status
ssh-user-manager status
```

### SSL Certificate Management

```bash
# Generate new SSL certificate
ssl-cert-manager generate

# Show certificate status
ssl-cert-manager status

# Show certificate information
ssl-cert-manager info

# Verify certificate
ssl-cert-manager verify
```

### Monitoring

```bash
# Run monitoring cycle
ssh-monitor monitor

# Quick status check
ssh-monitor status

# Check system health
ssh-monitor health

# Generate usage report
ssh-monitor report

# Install automated monitoring (every 6 hours)
ssh-monitor install-cron

# Install with custom schedule (every 4 hours)
ssh-monitor install-cron "0 */4 * * *"
```

## Security Features

### TLSv1.3 Configuration
- **Cipher Suite**: TLS_AES_256_GCM_SHA384
- **Key Exchange**: Perfect Forward Secrecy
- **Authentication**: RSA 4096-bit certificates
- **Protocol**: TLSv1.3 only (older versions disabled)

### SSH Security
- Root login disabled
- Key-based authentication preferred
- Connection timeouts configured
- Failed attempt limits
- Session monitoring

### System Security
- Automatic expired user cleanup
- Session monitoring and alerting
- Log rotation and management
- Firewall configuration
- Certificate expiration monitoring

## HTTP Injector Compatibility

This system is specifically configured for use with HTTP Injector app:
- **Protocol**: SSL/TLS proxy - SSH
- **Port**: 443 (matches your preference)
- **Security**: TLSv1.3 with AES-256-GCM encryption
- **Connection**: Direct SSH over SSL tunnel

### HTTP Injector Configuration
```
Server Type: SSH
Protocol: SSL/TLS proxy
Server Address: your-server-ip
Server Port: 443
Username: [created username]
Authentication: SSH Key or Password
```

## File Structure

```
/opt/ssh-user-manager/
├── ssh_user_manager.sh     # Main user management script
├── generate_ssl_cert.sh    # SSL certificate generator
├── monitor_cleanup.sh      # Monitoring and cleanup
├── manager.conf           # Configuration file
└── users.db              # User database

/etc/stunnel/
├── stunnel.conf          # Stunnel configuration
├── stunnel.pem          # SSL certificate + key
├── stunnel.key          # Private key
└── stunnel.crt          # Certificate

/usr/local/bin/
├── ssh-user-manager     # Symlink to user manager
├── ssl-cert-manager     # Symlink to cert manager
└── ssh-monitor         # Symlink to monitor
```

## Monitoring and Alerts

### Automated Monitoring
- System health checks
- Service status monitoring
- User session tracking
- Certificate expiration warnings
- Disk and memory usage alerts

### Email Notifications
Edit `monitor_cleanup.sh` to enable email alerts:
```bash
EMAIL_ALERTS=true
ADMIN_EMAIL="admin@your-domain.com"
```

### Log Files
- Installation: `/var/log/ssh_user_manager_install.log`
- User Management: `/var/log/ssh_user_manager.log`
- Monitoring: `/var/log/ssh_user_monitor.log`
- Stunnel: `/var/log/stunnel/stunnel.log`

## Troubleshooting

### Common Issues

**1. Stunnel not starting**
```bash
# Check configuration
sudo stunnel -test /etc/stunnel/stunnel.conf

# Check certificate
ssl-cert-manager verify

# View logs
sudo journalctl -u stunnel -f
```

**2. SSH connection refused**
```bash
# Check SSH service
sudo systemctl status ssh

# Check port binding
sudo netstat -tlnp | grep :443

# Test local SSH
ssh localhost
```

**3. Certificate issues**
```bash
# Regenerate certificate
sudo ssl-cert-manager generate

# Check certificate validity
ssl-cert-manager status
```

### System Status Check
```bash
# Quick system overview
ssh-monitor status

# Detailed health check
ssh-monitor health

# View active sessions
ssh-monitor sessions
```

## Performance Tuning

### For High User Loads
1. Increase `MAX_USERS` in `manager.conf`
2. Adjust SSH `MaxSessions` and `MaxStartups`
3. Configure connection pooling
4. Monitor system resources

### For Security Hardening
1. Enable client certificate verification
2. Implement IP-based restrictions
3. Configure fail2ban integration
4. Enable detailed logging

## Updates and Maintenance

### Updating the System
```bash
# Update scripts while preserving configuration
sudo ./install.sh update

# Full reinstallation
sudo ./install.sh uninstall
sudo ./install.sh install
```

### Certificate Renewal
```bash
# Check certificate expiration
ssl-cert-manager status

# Generate new certificate
sudo ssl-cert-manager generate

# Restart stunnel
sudo systemctl restart stunnel
```

### Backup and Restore
```bash
# Backup user database and configuration
sudo cp /opt/ssh-user-manager/users.db /backup/
sudo cp /opt/ssh-user-manager/manager.conf /backup/
sudo cp -r /etc/stunnel/ /backup/

# Restore from backup
sudo cp /backup/users.db /opt/ssh-user-manager/
sudo cp /backup/manager.conf /opt/ssh-user-manager/
sudo cp -r /backup/stunnel/ /etc/
```

## License

This project is open source. Use at your own risk and ensure compliance with your local laws and regulations.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review log files for error messages
3. Verify system status with monitoring commands
4. Ensure all dependencies are properly installed

## Contributing

Contributions are welcome! Please ensure any modifications maintain the security standards and compatibility with the HTTP Injector app requirements.

---

**Security Notice**: This system is designed for authorized use only. Ensure you have proper authorization before deploying on any server and comply with all applicable laws and policies.
