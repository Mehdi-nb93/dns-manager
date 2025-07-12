#!/bin/bash

CONFIG_DIR="/etc/cf-dns"
CONFIG_FILE="$CONFIG_DIR/config"
INSTALL_PATH="/usr/local/bin/cf-dns"
SCRIPT_PATH="$(realpath "$0")"

mkdir -p "$CONFIG_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Step 1: Get API Token
get_api_token() {
    echo -e "\n🔐 ${YELLOW}Enter your Cloudflare API Token:${NC}"
    read -rp "API Token: " CF_API_TOKEN
}

# Step 2: Get Domain
get_domain() {
    echo -e "\n🌐 ${YELLOW}Enter your domain (e.g., example.com):${NC}"
    read -rp "Domain: " CF_DOMAIN
}

# Step 3: Validate
validate_token_and_zone() {
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_DOMAIN" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo -e "${RED}❌ Invalid token or domain. Please try again.${NC}"
        return 1
    else
        echo "CF_API_TOKEN=$CF_API_TOKEN" > "$CONFIG_FILE"
        echo "CF_DOMAIN=$CF_DOMAIN" >> "$CONFIG_FILE"
        echo "ZONE_ID=$ZONE_ID" >> "$CONFIG_FILE"
        echo -e "${GREEN}✅ Token and domain are valid.${NC}"
        return 0
    fi
}

# Load saved config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Ask for info if not set
while [[ -z "$CF_API_TOKEN" || -z "$CF_DOMAIN" || -z "$ZONE_ID" ]]; do
    get_api_token
    get_domain
    validate_token_and_zone || continue
done

# Get IP
get_public_ip() {
    curl -s https://api.ipify.org
}

# Add DNS
add_dns_record() {
    read -rp "Subdomain (e.g., sub.$CF_DOMAIN): " subdomain
    read -rp "Custom IP (leave blank for server IP): " custom_ip
    ip=${custom_ip:-$(get_public_ip)}

    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}")

    if echo "$response" | grep -q '"success":true'; then
        echo -e "${GREEN}✅ DNS record added successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to add record:${NC}"
        echo "$response"
    fi
}

# Delete DNS
delete_dns_record() {
    records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    echo -e "\n📄 ${YELLOW}Available DNS records:${NC}"
    echo "$records" | jq -r '.result[] | "\(.name) => \(.id)"' | nl -w2 -s'. '

    mapfile -t ids < <(echo "$records" | jq -r '.result[].id')
    mapfile -t names < <(echo "$records" | jq -r '.result[].name')

    read -rp "Select record number to delete: " index
    record_id=${ids[$((index - 1))]}
    record_name=${names[$((index - 1))]}

    if [ -n "$record_id" ]; then
        read -rp "Are you sure you want to delete '$record_name'? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json"
            echo -e "${GREEN}✅ DNS record deleted.${NC}"
        else
            echo -e "${YELLOW}Cancelled.${NC}"
        fi
    else
        echo -e "${RED}❌ Invalid selection.${NC}"
    fi
}

# Clear API token only
clear_api_token() {
    rm -f "$CONFIG_FILE"
    unset CF_API_TOKEN CF_DOMAIN ZONE_ID
    echo -e "${GREEN}✅ API token and config cleared.${NC}"
}

# Full uninstall
full_uninstall() {
    echo -e "\n⚠️ ${RED}This will remove the entire script and all config files.${NC}"
    read -rp "Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        rm -f "$CONFIG_FILE"
        rm -rf "$CONFIG_DIR"
        [[ -f "$INSTALL_PATH" ]] && rm -f "$INSTALL_PATH"
        [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]] && rm -f "$SCRIPT_PATH"
        echo -e "${GREEN}✅ Script and config fully removed.${NC}"
        exit 0
    else
        echo -e "${YELLOW}Uninstall canceled.${NC}"
    fi
}

# Menu
while true; do
    echo -e "\n${YELLOW}--- Cloudflare DNS Manager ---${NC}"
    echo "1) Add DNS record"
    echo "2) Delete DNS record"
    echo "3) Clear saved API token"
    echo "4) Uninstall script completely"
    echo "5) Exit"
    read -rp "Select an option: " choice

    case "$choice" in
        1) add_dns_record ;;
        2) delete_dns_record ;;
        3) clear_api_token ;;
        4) full_uninstall ;;
        5) echo "👋 Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}" ;;
    esac
done
