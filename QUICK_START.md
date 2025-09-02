# Quick Start Guide

## SSH User Manager for Stunnel - TLSv1.3 Secure Setup

### 🚀 One-Command Installation

```bash
sudo ./install.sh install
```

This will automatically:
- Install all dependencies (stunnel, SSH, OpenSSL)
- Generate TLSv1.3 SSL certificates
- Configure stunnel with TLS_AES_256_GCM_SHA384 cipher
- Set up secure SSH configuration
- Configure firewall rules for port 443
- Install monitoring and cleanup automation

### 👤 Create Your First User

```bash
# Create user with SSH key (recommended)
sudo ssh-user-manager create john 30

# Create user with password
sudo ssh-user-manager create jane 7 --password
```

### 📱 HTTP Injector Configuration

**Connection Settings:**
- **Server Type**: SSH
- **Protocol**: SSL/TLS proxy - SSH  
- **Server IP**: Your server's IP address
- **Port**: 443
- **Username**: Created username
- **Authentication**: SSH Key or Password

### 🔐 Security Features

- **TLSv1.3**: Latest TLS protocol
- **Cipher**: TLS_AES_256_GCM_SHA384 (256-bit encryption)
- **Port**: 443 (HTTPS standard port)
- **Certificate**: 4096-bit RSA with SHA-384
- **User Limits**: Configurable max users (default: 50)
- **Auto-Expiry**: Automatic user cleanup

### 📊 Management Commands

```bash
# List all users
ssh-user-manager list

# Check system status
ssh-user-manager status

# Monitor system health
ssh-monitor status

# View active sessions
ssh-monitor sessions
```

### 🔧 Configuration

Default settings in `/opt/ssh-user-manager/manager.conf`:
- Max users: 50
- Default expiration: 30 days
- Port: 443
- Auto-cleanup: Every 6 hours

### 📞 Connection Test

```bash
# From client (replace with your server IP)
ssh username@YOUR_SERVER_IP -p 443
```

### ⚠️ Important Notes

1. **Firewall**: Ensure port 443 is open
2. **Root Access**: Installation requires sudo/root privileges  
3. **Certificate**: Auto-generated self-signed certificate
4. **Monitoring**: Automated cleanup runs every 6 hours
5. **Logs**: Check `/var/log/ssh_user_manager*.log` for issues

### 🆘 Troubleshooting

**Connection Issues:**
```bash
# Check services
sudo systemctl status stunnel
sudo systemctl status ssh

# Check port
sudo netstat -tlnp | grep :443

# View logs
sudo journalctl -u stunnel -f
```

**Certificate Issues:**
```bash
# Regenerate certificate
sudo ssl-cert-manager generate

# Verify certificate
ssl-cert-manager verify
```

### 🔄 Updates

```bash
# Update system (preserves config)
sudo ./install.sh update

# Complete reinstall
sudo ./install.sh uninstall
sudo ./install.sh install
```

---

**Ready to go!** Your SSH tunneling system is now configured for secure connections through port 443 with TLSv1.3 encryption, perfect for use with HTTP Injector app.
