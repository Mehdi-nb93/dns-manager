#!/bin/bash

CONFIG_FILE="$HOME/.cf-dns-config"

function ask_config() {
  echo "تنظیمات اولیه Cloudflare DNS Manager"

  read -p "توکن API کلودفلر (CF_API_TOKEN): " api_token
  read -p "نام دامنه (ZONE_NAME): " zone_name

  echo -e "API_TOKEN=\"$api_token\"\nZONE_NAME=\"$zone_name\"\nPROXIED=false\nTTL=120" > "$CONFIG_FILE"
  echo "تنظیمات ذخیره شد در: $CONFIG_FILE"
}

function show_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "=== کانفیگ فعلی ==="
    cat "$CONFIG_FILE"
    echo "===================="
  else
    echo "کانفیگی یافت نشد."
  fi
}

function edit_config() {
  echo "ویرایش تنظیمات..."

  read -p "توکن API کلودفلر (خالی برای بدون تغییر): " api_token
  read -p "نام دامنه (خالی برای بدون تغییر): " zone_name

  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  fi

  if [[ -n "$api_token" ]]; then
    API_TOKEN="$api_token"
  fi
  if [[ -n "$zone_name" ]]; then
    ZONE_NAME="$zone_name"
  fi

  echo -e "API_TOKEN=\"$API_TOKEN\"\nZONE_NAME=\"$ZONE_NAME\"\nPROXIED=false\nTTL=120" > "$CONFIG_FILE"
  echo "کانفیگ بروزرسانی شد."
}

function delete_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
    echo "کانفیگ حذف شد."
  else
    echo "کانفیگی برای حذف یافت نشد."
  fi
}

function config_menu() {
  while true; do
    echo ""
    echo "مدیریت کانفیگ Cloudflare DNS"
    echo "1) نمایش کانفیگ"
    echo "2) ویرایش کانفیگ"
    echo "3) حذف کانفیگ"
    echo "4) ادامه اجرا"
    echo "0) خروج"
    read -p "انتخاب شما: " choice

    case $choice in
      1) show_config ;;
      2) edit_config ;;
      3) delete_config ;;
      4) break ;;
      0) echo "خروج..."; exit 0 ;;
      *) echo "انتخاب نامعتبر." ;;
    esac
  done
}

# اجرای منوی کانفیگ در ابتدا
config_menu

# بارگذاری تنظیمات
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "کانفیگ موجود نیست. لطفا تنظیمات را وارد کنید."
  ask_config
fi

source "$CONFIG_FILE"

if [[ -z "$API_TOKEN" || -z "$ZONE_NAME" ]]; then
  echo "تنظیمات ناقص است، لطفا مجدداً تنظیمات را وارد کنید."
  ask_config
  source "$CONFIG_FILE"
fi

# بررسی ورودی ها
if [[ $# -lt 2 ]]; then
  echo "نحوه استفاده:"
  echo "  $0 create|update|delete رکورد_کامل"
  exit 1
fi

ACTION=$1
RECORD_NAME=$2
RECORD_TYPE="A"
PROXIED=${PROXIED:-false}
TTL=${TTL:-120}

# گرفتن IP عمومی
PUBLIC_IP=$(curl -s https://api.ipify.org)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ آی‌پی عمومی پیدا نشد."
  exit 1
fi
echo "IP عمومی فعلی سرور: $PUBLIC_IP"

# پرسش از کاربر برای وارد کردن IP دلخواه یا استفاده از IP سرور
read -p "اگر می‌خواهید IP متفاوتی وارد کنید، آن را تایپ کنید، در غیر این صورت Enter بزنید: " CUSTOM_IP
if [[ -n "$CUSTOM_IP" ]]; then
  IP_TO_USE="$CUSTOM_IP"
else
  IP_TO_USE="$PUBLIC_IP"
fi

echo "IP نهایی استفاده شده: $IP_TO_USE"

# گرفتن Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
  echo "❌ Zone ID پیدا نشد."
  exit 1
fi

# جستجوی رکورد موجود
RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${RECORD_TYPE}&name=${RECORD_NAME}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_INFO" | jq -r '.result[0].id')

# انجام عملیات
case $ACTION in
  create|update)
    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
      echo "در حال ساخت رکورد $RECORD_NAME با IP $IP_TO_USE..."
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$RECORD_TYPE\",\"name\":\"$RECORD_NAME\",\"content\":\"$IP_TO_USE\",\"ttl\":$TTL,\"proxied\":$PROXIED}" | jq
      echo "✅ رکورد ساخته شد."
    else
      echo "در حال آپدیت رکورد $RECORD_NAME به IP $IP_TO_USE..."
      curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$RECORD_TYPE\",\"name\":\"$RECORD_NAME\",\"content\":\"$IP_TO_USE\",\"ttl\":$TTL,\"proxied\":$PROXIED}" | jq
      echo "✅ رکورد آپدیت شد."
    fi
    ;;
  delete)
    if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
      echo "رکوردی برای حذف یافت نشد."
    else
      echo "در حال حذف رکورد $RECORD_NAME..."
      curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" | jq
      echo "✅ رکورد حذف شد."
    fi
    ;;
  *)
    echo "دستور نامعتبر است. فقط create, update, delete مجاز است."
    exit 1
    ;;
esac
