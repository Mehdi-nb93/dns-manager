#!/bin/bash

# رنگ‌ها برای زیبایی
GREEN='\033[0;32m'
NC='\033[0m'

# آدرس فایل اصلی
REPO_URL="https://raw.githubusercontent.com/mehdi-nb93/dns-manager/main/cf-dnsrecord.sh"
INSTALL_PATH="/usr/local/bin/cf-dnsrecord"
CONFIG_DIR="/etc/cf-dnsrecord"
CONFIG_FILE="$CONFIG_DIR/config"

echo -e "${GREEN}[+] نصب ابزار مدیریت DNS کلودفلر...${NC}"

# ساخت مسیر پیکربندی
mkdir -p "$CONFIG_DIR"

# دریافت اسکریپت اصلی
curl -fsSL "$REPO_URL" -o "$INSTALL_PATH"

# بررسی موفقیت دانلود
if [ ! -s "$INSTALL_PATH" ]; then
    echo "❌ دانلود اسکریپت ناموفق بود. آدرس بررسی شود."
    exit 1
fi

# مجوز اجرایی
chmod +x "$INSTALL_PATH"

# نمایش دستور استفاده
echo -e "${GREEN}[✓] نصب با موفقیت انجام شد.${NC}"
echo -e "📌 حالا می‌تونی از دستور زیر استفاده کنی:"
echo -e "${GREEN}cf-dnsrecord${NC}"
