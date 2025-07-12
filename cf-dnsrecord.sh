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

function list_dns_records() {
  local zone_id=$1
  local name_filter=$2

  curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$name_filter" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json"
}

function delete_dns_record() {
  local zone_id=$1
  local record_id=$2

  curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json"
}

clear
echo "---- Cloudflare DNS Manager ----"
load_config

if [[ -z "$CF_API_TOKEN" ]]; then
  read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
fi

if [[ -z "$CF_ZONE" ]]; then
  read -p "Enter your domain (zone) name (e.g. example.com): " CF_ZONE
fi

save_config

zone_id=$(get_zone_id)

if [[ "$zone_id" == "null" || -z "$zone_id" ]]; then
  echo "❌ Error: Zone ID پیدا نشد. API Token یا دامنه را بررسی کن."
  exit 1
fi

echo ""
echo "✅ Zone ID: $zone_id"
echo ""
echo "Choose an action:"
echo "1) Add DNS record"
echo "2) Delete DNS record"
echo "3) Remove this tool and config completely"
read -p "Enter choice [1, 2 or 3]: " ACTION

if [[ "$ACTION" == "1" ]]; then
  DEFAULT_IP=$(curl -s https://api.ipify.org)
  read -p "Enter IP for DNS record (Press Enter to use server IP $DEFAULT_IP): " IP_INPUT
  if [[ -z "$IP_INPUT" ]]; then
    IP_INPUT=$DEFAULT_IP
  fi
  read -p "Enter DNS record name (e.g. sub.example.com): " RECORD_NAME
  if [[ -z "$RECORD_NAME" ]]; then
    echo "❌ No record name entered."
    exit 0
  fi
  response=$(add_dns_record "$zone_id" "$RECORD_NAME" "$IP_INPUT")
  success=$(echo "$response" | jq -r '.success')
  if [[ "$success" == "true" ]]; then
    echo "✅ DNS record added."
  else
    echo "❌ Failed to add DNS record:"
    echo "$response" | jq -r '.errors[]?.message'
  fi

elif [[ "$ACTION" == "2" ]]; then
  read -p "Enter record name to search (e.g. sub.example.com): " DEL_NAME
  records_json=$(list_dns_records "$zone_id" "$DEL_NAME")
  count=$(echo "$records_json" | jq '.result | length')

  if [[ "$count" -eq 0 ]]; then
    echo "❌ No DNS records found."
    exit 0
  fi

  echo ""
  echo "Found $count record(s):"
  mapfile -t ids < <(echo "$records_json" | jq -r '.result[].id')
  mapfile -t names < <(echo "$records_json" | jq -r '.result[].name')
  mapfile -t contents < <(echo "$records_json" | jq -r '.result[].content')

  for i in "${!ids[@]}"; do
    echo "$((i+1))) ${names[$i]} -> ${contents[$i]}"
  done

  read -p "Enter number of record to delete: " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > count )); then
    echo "❌ Invalid selection."
    exit 1
  fi

  DEL_ID="${ids[$((choice-1))]}"
  delete_response=$(delete_dns_record "$zone_id" "$DEL_ID")
  success=$(echo "$delete_response" | jq -r '.success')
  if [[ "$success" == "true" ]]; then
    echo "✅ DNS record deleted."
  else
    echo "❌ Failed to delete:"
    echo "$delete_response" | jq -r '.errors[]?.message'
  fi

elif [[ "$ACTION" == "3" ]]; then
  echo "⚠️ این کار کل ابزار (cf-dnsrecord) و تنظیمات ذخیره‌شده رو پاک می‌کنه!"
  read -p "ادامه؟ (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -f "$CONFIG_FILE"
    SCRIPT_PATH=$(readlink -f "$0")
    if [[ "$SCRIPT_PATH" == "/usr/local/bin/cf-dnsrecord" ]]; then
      rm -f "$SCRIPT_PATH"
      echo "🗑️ ابزار cf-dnsrecord نیز حذف شد."
    fi
    echo "✅ همه چیز پاک شد."
  else
    echo "❎ لغو شد."
  fi
  exit 0

else
  echo "❌ Invalid choice."
  exit 1
fi
