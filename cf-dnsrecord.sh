#!/bin/bash

CONFIG_DIR="/etc/cf-dns"
CONFIG_FILE="$CONFIG_DIR/config"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$CONFIG_DIR"

# Prompt user to input API token
get_api_token() {
    echo -e "\n🔐 ${YELLOW}Enter your Cloudflare API Token:${NC}"
    read -rp "API Token: " CF_API_TOKEN
    echo "CF_API_TOKEN=$CF_API_TOKEN" > "$CONFIG_FILE"
}

# API token validation loop
while true; do
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    if [ -z "$CF_API_TOKEN" ]; then
        get_api_token
        continue
    fi

    echo -e "\n${YELLOW}Verifying API Token...${NC}"
    verify=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$verify" | grep -q '"success":true'; then
        echo -e "${GREEN}✅ API Token is valid.${NC}"
        break
    else
        echo -e "${RED}❌ Invalid API Token.${NC}"
        get_api_token
    fi
done

# Get Cloudflare zone_id
get_zone_id() {
    local domain="$1"
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id'
}

# Get server IP
get_public_ip() {
    curl -s https://api.ipify.org
}

# Add DNS record
add_dns_record() {
    read -rp "Domain (e.g., example.com): " domain
    read -rp "Subdomain (e.g., sub.example.com): " subdomain
    read -rp "Custom IP (leave empty to use server IP): " custom_ip
    ip=${custom_ip:-$(get_public_ip)}

    zone_id=$(get_zone_id "$domain")

    if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
        echo -e "${RED}❌ Zone not found for this domain.${NC}"
        return
    fi

    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}")

    if echo "$response" | grep -q '"success":true'; then
        echo -e "${GREEN}✅ DNS record added successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to add DNS record:${NC}"
        echo "$response"
    fi
}

# Delete DNS record
delete_dns_record() {
    read -rp "Domain (e.g., example.com): " domain
    zone_id=$(get_zone_id "$domain")

    records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    echo -e "\n📄 ${YELLOW}Existing DNS records:${NC}"
    echo "$records" | jq -r '.result[] | "\(.name) => \(.id)"' | nl -w2 -s'. '

    mapfile -t ids < <(echo "$records" | jq -r '.result[].id')
    mapfile -t names < <(echo "$records" | jq -r '.result[].name')

    read -rp "Enter record number to delete: " index
    record_id=${ids[$((index - 1))]}
    record_name=${names[$((index - 1))]}

    if [ -n "$record_id" ]; then
        read -rp "Are you sure you want to delete '$record_name'? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json"
            echo -e "${GREEN}✅ DNS record deleted.${NC}"
        else
            echo "❎ Cancelled."
        fi
    else
        echo -e "${RED}❌ Invalid selection.${NC}"
    fi
}

# Clear API token from config
clear_api_token() {
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        echo -e "${GREEN}✅ API Token removed.${NC}"
    else
        echo -e "${YELLOW}No API Token stored.${NC}"
    fi
}

# Main menu
while true; do
    echo -e "\n${YELLOW}--- Cloudflare DNS Manager ---${NC}"
    echo "1) Add new DNS record"
    echo "2) Delete a DNS record"
    echo "3) Remove stored API Token"
    echo "4) Exit"
    read -rp "Choose an option: " choice

    case "$choice" in
        1) add_dns_record ;;
        2) delete_dns_record ;;
        3) clear_api_token ;;
        4) echo "👋 Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${NC}" ;;
    esac
done
