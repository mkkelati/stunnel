#!/bin/bash

# SSL Certificate Generator for Stunnel
# Generates self-signed certificates optimized for TLSv1.3

# Configuration
CERT_DIR="/etc/stunnel"
CERT_FILE="$CERT_DIR/stunnel.pem"
KEY_FILE="$CERT_DIR/stunnel.key"
CSR_FILE="$CERT_DIR/stunnel.csr"
CONFIG_FILE="$CERT_DIR/openssl.cnf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Certificate validity (in days)
CERT_VALIDITY=365

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Create certificate directory
create_cert_dir() {
    if [[ ! -d "$CERT_DIR" ]]; then
        mkdir -p "$CERT_DIR"
        echo -e "${GREEN}Created certificate directory: $CERT_DIR${NC}"
    fi
    chmod 700 "$CERT_DIR"
}

# Get server information
get_server_info() {
    echo -e "${BLUE}Setting up SSL certificate for Stunnel${NC}"
    echo "Please provide the following information:"
    
    read -p "Country (2 letter code) [US]: " COUNTRY
    COUNTRY=${COUNTRY:-US}
    
    read -p "State/Province [California]: " STATE
    STATE=${STATE:-California}
    
    read -p "City [San Francisco]: " CITY
    CITY=${CITY:-San Francisco}
    
    read -p "Organization [Your Organization]: " ORG
    ORG=${ORG:-Your Organization}
    
    read -p "Organizational Unit [IT Department]: " OU
    OU=${OU:-IT Department}
    
    read -p "Common Name (server FQDN or IP) [$(hostname -f 2>/dev/null || hostname)]: " CN
    CN=${CN:-$(hostname -f 2>/dev/null || hostname)}
    
    read -p "Email [admin@$(hostname -d 2>/dev/null || echo "example.com")]: " EMAIL
    EMAIL=${EMAIL:-admin@$(hostname -d 2>/dev/null || echo "example.com")}
    
    echo -e "${YELLOW}Certificate will be valid for $CERT_VALIDITY days${NC}"
}

# Create OpenSSL configuration
create_openssl_config() {
    cat > "$CONFIG_FILE" << EOF
[req]
default_bits = 4096
default_keyfile = $KEY_FILE
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $OU
CN = $CN
emailAddress = $EMAIL

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

    # Add server IP if available
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
    if [[ -n "$server_ip" ]]; then
        echo "IP.2 = $server_ip" >> "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}Created OpenSSL configuration: $CONFIG_FILE${NC}"
}

# Generate private key
generate_private_key() {
    echo -e "${BLUE}Generating 4096-bit RSA private key...${NC}"
    
    openssl genrsa -out "$KEY_FILE" 4096
    if [[ $? -eq 0 ]]; then
        chmod 600 "$KEY_FILE"
        echo -e "${GREEN}Private key generated: $KEY_FILE${NC}"
    else
        echo -e "${RED}Error generating private key${NC}"
        exit 1
    fi
}

# Generate certificate signing request
generate_csr() {
    echo -e "${BLUE}Generating certificate signing request...${NC}"
    
    openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}CSR generated: $CSR_FILE${NC}"
    else
        echo -e "${RED}Error generating CSR${NC}"
        exit 1
    fi
}

# Generate self-signed certificate
generate_certificate() {
    echo -e "${BLUE}Generating self-signed certificate...${NC}"
    
    openssl x509 -req -days "$CERT_VALIDITY" -in "$CSR_FILE" -signkey "$KEY_FILE" -out "$CERT_FILE" -extensions v3_req -extfile "$CONFIG_FILE"
    if [[ $? -eq 0 ]]; then
        chmod 644 "$CERT_FILE"
        echo -e "${GREEN}Certificate generated: $CERT_FILE${NC}"
    else
        echo -e "${RED}Error generating certificate${NC}"
        exit 1
    fi
}

# Combine certificate and key for stunnel
create_stunnel_pem() {
    echo -e "${BLUE}Creating combined PEM file for stunnel...${NC}"
    
    # Stunnel expects cert and key in one file
    local stunnel_pem="$CERT_DIR/stunnel.pem"
    cat "$CERT_FILE" "$KEY_FILE" > "$stunnel_pem"
    chmod 600 "$stunnel_pem"
    
    echo -e "${GREEN}Stunnel PEM file created: $stunnel_pem${NC}"
}

# Display certificate information
show_certificate_info() {
    echo -e "${BLUE}Certificate Information:${NC}"
    echo "----------------------------------------"
    openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:|DNS:|IP Address:)"
    echo "----------------------------------------"
    
    echo -e "${YELLOW}Certificate files created:${NC}"
    echo "  Certificate: $CERT_FILE"
    echo "  Private Key: $KEY_FILE"
    echo "  Stunnel PEM: $CERT_DIR/stunnel.pem"
    echo "  CSR: $CSR_FILE"
    echo "  OpenSSL Config: $CONFIG_FILE"
}

# Verify certificate
verify_certificate() {
    echo -e "${BLUE}Verifying certificate...${NC}"
    
    # Check certificate validity
    if openssl x509 -in "$CERT_FILE" -noout -checkend 0 >/dev/null 2>&1; then
        echo -e "${GREEN}Certificate is valid${NC}"
    else
        echo -e "${RED}Certificate is invalid or expired${NC}"
        return 1
    fi
    
    # Check if private key matches certificate
    local cert_md5=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
    local key_md5=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)
    
    if [[ "$cert_md5" == "$key_md5" ]]; then
        echo -e "${GREEN}Private key matches certificate${NC}"
    else
        echo -e "${RED}Private key does not match certificate${NC}"
        return 1
    fi
    
    return 0
}

# Backup existing certificates
backup_existing() {
    local backup_dir="$CERT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$CERT_FILE" ]] || [[ -f "$KEY_FILE" ]]; then
        echo -e "${YELLOW}Backing up existing certificates...${NC}"
        mkdir -p "$backup_dir"
        
        [[ -f "$CERT_FILE" ]] && cp "$CERT_FILE" "$backup_dir/"
        [[ -f "$KEY_FILE" ]] && cp "$KEY_FILE" "$backup_dir/"
        [[ -f "$CERT_DIR/stunnel.pem" ]] && cp "$CERT_DIR/stunnel.pem" "$backup_dir/"
        
        echo -e "${GREEN}Backup created: $backup_dir${NC}"
    fi
}

# Main certificate generation function
generate_ssl_certificate() {
    echo -e "${BLUE}SSL Certificate Generator for Stunnel${NC}"
    echo -e "${BLUE}TLSv1.3 optimized certificate generation${NC}"
    echo "========================================"
    
    # Check for existing certificates
    if [[ -f "$CERT_FILE" ]] && [[ -f "$KEY_FILE" ]]; then
        echo -e "${YELLOW}Existing certificates found${NC}"
        read -p "Do you want to replace them? (y/N): " replace
        if [[ ! "$replace" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Keeping existing certificates${NC}"
            show_certificate_info
            return 0
        fi
        backup_existing
    fi
    
    # Create certificate directory
    create_cert_dir
    
    # Get server information
    get_server_info
    
    # Generate certificate components
    create_openssl_config
    generate_private_key
    generate_csr
    generate_certificate
    create_stunnel_pem
    
    # Verify and display results
    if verify_certificate; then
        show_certificate_info
        echo -e "${GREEN}SSL certificate generation completed successfully!${NC}"
        echo -e "${YELLOW}You can now start stunnel with the generated certificate${NC}"
        
        # Clean up CSR file
        rm -f "$CSR_FILE"
        
        return 0
    else
        echo -e "${RED}Certificate verification failed${NC}"
        return 1
    fi
}

# Show certificate status
show_status() {
    echo -e "${BLUE}Certificate Status:${NC}"
    echo "----------------------------------------"
    
    if [[ -f "$CERT_FILE" ]]; then
        echo -e "Certificate file: ${GREEN}exists${NC}"
        
        # Check expiration
        local expiry_date=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
        echo "Expires: $expiry_date"
        
        # Check if expiring soon (30 days)
        if openssl x509 -in "$CERT_FILE" -noout -checkend 2592000 >/dev/null 2>&1; then
            echo -e "Status: ${GREEN}valid${NC}"
        else
            echo -e "Status: ${YELLOW}expires within 30 days${NC}"
        fi
    else
        echo -e "Certificate file: ${RED}missing${NC}"
    fi
    
    if [[ -f "$KEY_FILE" ]]; then
        echo -e "Private key: ${GREEN}exists${NC}"
    else
        echo -e "Private key: ${RED}missing${NC}"
    fi
    
    if [[ -f "$CERT_DIR/stunnel.pem" ]]; then
        echo -e "Stunnel PEM: ${GREEN}exists${NC}"
    else
        echo -e "Stunnel PEM: ${RED}missing${NC}"
    fi
    
    echo "----------------------------------------"
}

# Show usage
show_usage() {
    echo -e "${BLUE}SSL Certificate Generator for Stunnel${NC}"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  generate    Generate new SSL certificate"
    echo "  status      Show certificate status"
    echo "  info        Show certificate information"
    echo "  verify      Verify existing certificate"
    echo ""
    echo "Files:"
    echo "  Certificate: $CERT_FILE"
    echo "  Private Key: $KEY_FILE"
    echo "  Stunnel PEM: $CERT_DIR/stunnel.pem"
}

# Main function
main() {
    case "${1:-generate}" in
        generate)
            check_root
            generate_ssl_certificate
            ;;
        status)
            show_status
            ;;
        info)
            if [[ -f "$CERT_FILE" ]]; then
                show_certificate_info
            else
                echo -e "${RED}No certificate found${NC}"
                exit 1
            fi
            ;;
        verify)
            if verify_certificate; then
                echo -e "${GREEN}Certificate verification passed${NC}"
            else
                echo -e "${RED}Certificate verification failed${NC}"
                exit 1
            fi
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"
