# 🚀 One-Click Installation from GitHub

## SSH User Manager for Stunnel - TLSv1.3 Secure System

### ⚡ Quick Installation

Copy and run this single command on your Linux server:

```bash
curl -sSL https://raw.githubusercontent.com/mkkelati/stunnel/main/install.sh | sudo bash -s install
```

**Or download and install manually:**

```bash
# Download the repository
wget https://github.com/mkkelati/stunnel/archive/refs/tags/v1.0.0.tar.gz
tar -xzf v1.0.0.tar.gz
cd stunnel-1.0.0

# Make installer executable and run
chmod +x install.sh
sudo ./install.sh install
```

### 🎯 What Gets Installed

- ✅ **Stunnel** with TLSv1.3 and TLS_AES_256_GCM_SHA384 encryption
- ✅ **SSH Server** with security hardening
- ✅ **User Management System** with limits and expiration
- ✅ **Interactive Menu Interface** for easy management
- ✅ **SSL Certificate Generation** (4096-bit RSA)
- ✅ **Automated Monitoring** and cleanup
- ✅ **Firewall Configuration** for port 443

### 🖥️ Start Using the System

After installation, simply type:

```bash
menu
```

This will launch the interactive menu where you can:

1. **Create User** - Add new SSH users with expiration dates
2. **Delete User** - Remove users safely
3. **List Users** - View all active and expired users  
4. **User Limits & Settings** - Configure max users, expiry defaults
5. **Stunnel Configuration** - Change port (default 443), manage service
6. **System Status & Monitoring** - Check health, view sessions
7. **SSL Certificate Management** - Generate/verify certificates
8. **Connection Information** - Get connection details for HTTP Injector
9. **System Installation/Update** - Manage the system

### 📱 HTTP Injector Setup

**Connection Settings for HTTP Injector:**
- **Server Type**: SSH
- **Protocol**: SSL/TLS proxy - SSH
- **Server Address**: Your server's IP address
- **Port**: 443 (or custom port if changed)
- **Username**: Created username
- **Password/Key**: As configured during user creation

### 🔧 Quick Commands

```bash
# Interactive menu (recommended)
menu

# Command line tools
ssh-user-manager create username 30        # Create user for 30 days
ssh-user-manager list                       # List all users
ssh-monitor status                          # Check system status
ssl-cert-manager generate                   # Generate new certificate
```

### 🔒 Security Features

- **TLSv1.3** protocol with **AES-256-GCM** encryption
- **Port 443** for stealth (appears as HTTPS traffic)
- **Perfect Forward Secrecy** with 4096-bit RSA certificates
- **User expiration** and **automatic cleanup**
- **Failed login protection** and **session monitoring**
- **Firewall integration** for secure access

### 🎮 System Requirements

- **OS**: Ubuntu 18.04+, Debian 9+, CentOS 7+, RHEL 7+
- **RAM**: Minimum 512MB (1GB+ recommended)
- **Storage**: 1GB free space
- **Network**: Internet access for installation
- **Privileges**: Root/sudo access required

### 🆘 Quick Troubleshooting

**Installation Issues:**
```bash
# Check if installation completed
sudo ./install.sh verify

# View installation logs
sudo tail -f /var/log/ssh_user_manager_install.log
```

**Service Issues:**
```bash
# Check services through menu
menu  # Select option 6 (System Status)

# Or command line
sudo systemctl status stunnel
sudo systemctl status ssh
```

**Connection Issues:**
```bash
# Test local SSH
ssh localhost

# Check if port 443 is listening
sudo netstat -tlnp | grep :443

# View stunnel logs
sudo tail -f /var/log/stunnel/stunnel.log
```

### 🔄 Updates

```bash
# Update to latest version
curl -sSL https://raw.githubusercontent.com/mkkelati/stunnel/main/install.sh | sudo bash -s update
```

### 📞 Support

- **Repository**: https://github.com/mkkelati/stunnel
- **Documentation**: See README.md in the repository
- **Quick Start**: See QUICK_START.md for fast setup guide

---

**🎉 Ready to Go!** Your secure SSH tunneling system is now configured and ready for HTTP Injector connections!
