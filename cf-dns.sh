#!/bin/bash

CONFIG_FILE="$HOME/.cf-dns-config"

function save_config() {
  echo "CF_API_TOKEN=\"$CF_API_TOKEN\"" > "$CONFIG_FILE"
  echo "CF_ZONE=\"$CF_ZONE\"" >> "$CONFIG_FILE"
}

function load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  fi
}

function get_zone_id() {
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id'
}

function add_dns_record() {
  local zone_id=$1
  local record_name=$2
  local record_ip=$3

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$record_ip\",\"proxied\":false}"
}

clear
echo "---- Cloudflare DNS Manager ----"
load_config

if [[ -z "$CF_API_TOKEN" ]]; then
  read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
fi

if [[ -z "$CF_ZONE" ]]; then
  read -p "Enter your domain (zone) name (e.g. nbm.of.to): " CF_ZONE
fi

save_config

zone_id=$(get_zone_id)

if [[ "$zone_id" == "null" || -z "$zone_id" ]]; then
  echo "Error: Could not find zone ID for domain $CF_ZONE. Check your API token and domain."
  exit 1
fi

echo "Zone ID found: $zone_id"

# شناسایی IP پیش‌فرض سرور
DEFAULT_IP=$(curl -s https://api.ipify.org)

read -p "Enter IP for DNS record (Press Enter to use server IP $DEFAULT_IP): " IP_INPUT

if [[ -z "$IP_INPUT" ]]; then
  IP_INPUT=$DEFAULT_IP
fi

read -p "Enter DNS record name (e.g. iran.nbm.of.to): " RECORD_NAME

if [[ -z "$RECORD_NAME" ]]; then
  echo "No record name entered. Exiting."
  exit 0
fi

response=$(add_dns_record "$zone_id" "$RECORD_NAME" "$IP_INPUT")

success=$(echo "$response" | jq -r '.success')

if [[ "$success" == "true" ]]; then
  echo "DNS record added successfully."
else
  echo "Failed to add DNS record:"
  echo "$response" | jq -r '.errors[]?.message'
fi
