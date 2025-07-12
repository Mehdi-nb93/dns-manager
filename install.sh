#!/bin/bash

INSTALL_PATH="/usr/local/bin/cf-dnsrecord"
SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/cf-dns.sh"  # ← تغییر بده

echo "⬇️ در حال نصب cf-dnsrecord از GitHub..."

curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"

if [[ ! -s "$INSTALL_PATH" ]]; then
  echo "❌ دریافت اسکریپت با مشکل مواجه شد. URL را بررسی کن."
  exit 1
fi

chmod +x "$INSTALL_PATH"

echo "✅ نصب انجام شد! حالا می‌تونی فقط با دستور زیر اجرا کنی:"
echo ""
echo "   cf-dnsrecord"
