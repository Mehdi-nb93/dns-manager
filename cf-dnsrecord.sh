#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

CONFIG_FILE="$HOME/.cf_dns_manager.conf"

get_api_token() {
    echo -e "\n🔐 Enter your Cloudflare API Token:"
    read -rp "API Token: " CF_API_TOKEN
}

validate_token_and_zone() {
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_DOMAIN" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    success=$(echo "$response" | jq -r '.success')
    if [[ "$success" != "true" ]]; then
        error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}❌ Error: $error_msg${NC}"

        while true; do
            echo -e "\n1) Re-enter API Token"
            echo "2) Exit"
            read -rp "Choose option: " opt
            case "$opt" in
                1)
                    get_api_token
                    echo -e "\nEnter your domain:"
                    read -rp "Domain: " CF_DOMAIN
                    validate_token_and_zone && break
                    ;;
                2)
                    echo "Goodbye!"
                    exit 0
                    ;;
                *)
                    echo "Invalid option."
                    ;;
            esac
        done
    fi

    ZONE_ID=$(echo "$response" | jq -r '.result[0].id')
    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo -e "${RED}❌ Zone ID not found for domain $CF_DOMAIN${NC}"
        return 1
    fi

    echo "CF_API_TOKEN=$CF_API_TOKEN" > "$CONFIG_FILE"
    echo "CF_DOMAIN=$CF_DOMAIN" >> "$CONFIG_FILE"
    echo "ZONE_ID=$ZONE_ID" >> "$CONFIG_FILE"
    echo "CF_IP=${CF_IP:-}" >> "$CONFIG_FILE"

    echo -e "${GREEN}✅ Token and domain are valid.${NC}"
    return 0
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

edit_ip() {
    echo -e "\nCurrent IP for DNS records is: ${CF_IP:-Not set}"
    echo "Enter new IP to use for DNS records (leave empty to use server public IP):"
    read -rp "IP: " new_ip
    if [[ -z "$new_ip" ]]; then
        CF_IP=""
    else
        CF_IP="$new_ip"
    fi
    grep -v "^CF_IP=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    echo "CF_IP=$CF_IP" >> "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo -e "${GREEN}✅ IP updated.${NC}"
}

add_dns_record() {
    echo -e "\nEnter subdomain (e.g. sub.yourdomain.com):"
    read -rp "Subdomain: " SUBDOMAIN

    if [[ -z "$CF_IP" ]]; then
        IP=$(curl -s https://api.ipify.org)
        echo "Using server IP: $IP"
    else
        IP="$CF_IP"
        echo "Using configured IP: $IP"
    fi

    data=$(jq -n \
        --arg type "A" \
        --arg name "$SUBDOMAIN" \
        --arg content "$IP" \
        --argjson proxied false \
        '{type: $type, name: $name, content: $content, ttl: 1, proxied: $proxied}')

    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$data")

    success=$(echo "$response" | jq -r '.success')
    if [[ "$success" == "true" ]]; then
        echo -e "${GREEN}✅ DNS record added successfully.${NC}"
    else
        error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}❌ Failed to add DNS record: $error_msg${NC}"
    fi
}

list_dns_records() {
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    success=$(echo "$response" | jq -r '.success')
    if [[ "$success" != "true" ]]; then
        error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}❌ Failed to list DNS records: $error_msg${NC}"
        return 1
    fi

    echo -e "\nDNS Records:"
    echo "$response" | jq -r '.result[] | "\(.id) \(.type) \(.name) \(.content)"'
}

delete_dns_record() {
    echo -e "\nFetching DNS records..."
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    success=$(echo "$response" | jq -r '.success')
    if [[ "$success" != "true" ]]; then
        error_msg=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}❌ Failed to fetch DNS records: $error_msg${NC}"
        return
    fi

    mapfile -t record_ids < <(echo "$response" | jq -r '.result[].id')
    mapfile -t record_names < <(echo "$response" | jq -r '.result[].name')

    echo -e "\nSelect a record to delete:"
    for i in "${!record_ids[@]}"; do
        echo "$((i+1))) ${record_names[i]}"
    done

    read -rp "Enter number: " num

    if ! [[ "$num" =~ ^[0-9]+$ ]] || ((num < 1 || num > ${#record_ids[@]})); then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi

    rec_id=${record_ids[$((num-1))]}
    rec_name=${record_names[$((num-1))]}

    read -rp "Are you sure you want to delete record $rec_name? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Deletion cancelled."
        return
    fi

    del_response=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rec_id" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    del_success=$(echo "$del_response" | jq -r '.success')
    if [[ "$del_success" == "true" ]]; then
        echo -e "${GREEN}✅ DNS record deleted successfully.${NC}"
    else
        del_error=$(echo "$del_response" | jq -r '.errors[0].message')
        echo -e "${RED}❌ Failed to delete DNS record: $del_error${NC}"
    fi
}

clear_api_token() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "\nYour current saved API Token is:"
        grep CF_API_TOKEN "$CONFIG_FILE" | cut -d'=' -f2
        echo
        read -rp "Are you sure you want to delete it? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            rm -f "$CONFIG_FILE"
            unset CF_API_TOKEN CF_DOMAIN ZONE_ID CF_IP
            echo -e "${GREEN}✅ API token and config cleared.${NC}"

            while true; do
                get_api_token
                echo -e "\nEnter your domain:"
                read -rp "Domain: " CF_DOMAIN
                validate_token_and_zone && break
            done
        else
            echo "Deletion canceled."
        fi
    else
        echo "No API token found."
    fi
}

remove_all() {
    echo -e "\nAre you sure you want to completely remove the script and all saved config? (y/n):"
    read -rp "> " confirm
    if [[ "$confirm" == "y" ]]; then
        rm -f "$CONFIG_FILE"
        script_path=$(realpath "$0")
        rm -f "$script_path"
        echo -e "${GREEN}✅ Script and config removed.${NC}"
        exit 0
    else
        echo "Operation canceled."
    fi
}

main_menu() {
    echo -e "\n===== Cloudflare DNS Manager ====="
    echo "1) Add DNS record"
    echo "2) Delete DNS record"
    echo "3) Show & Delete API Token"
    echo "4) Edit IP for DNS records"
    echo "5) Remove script and config completely"
    echo "6) Exit"
    read -rp "Choose an option: " choice

    case "$choice" in
        1) add_dns_record ;;
        2) delete_dns_record ;;
        3) clear_api_token ;;
        4) edit_ip ;;
        5) remove_all ;;
        6) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option." ;;
    esac
}

# Start

load_config

if [[ -z "$CF_API_TOKEN" || -z "$CF_DOMAIN" || -z "$ZONE_ID" ]]; then
    get_api_token
    echo -e "\nEnter your domain:"
    read -rp "Domain: " CF_DOMAIN
    validate_token_and_zone
fi

while true; do
    main_menu
done
