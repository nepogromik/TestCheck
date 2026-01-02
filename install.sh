#!/usr/bin/env bash

set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1 && ! command -v yum >/dev/null 2>&1; then
  echo "Поддерживаются только сервера на базе Debian/Ubuntu или RHEL/CentOS."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Скрипт нужно запускать от root (или через sudo)."
  exit 1
fi

read -rp "Введите домен (например, example.com): " DOMAIN
read -rp "Введите e-mail для Let's Encrypt: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "Домен и e-mail не могут быть пустыми."
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  PM="apt-get"
  $PM update
  $PM install -y nginx certbot python3-certbot-nginx git
else
  PM="yum"
  $PM install -y epel-release
  $PM install -y nginx certbot python3-certbot-nginx git
fi

systemctl enable nginx
systemctl start nginx

WEBROOT="/var/www/${DOMAIN}"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}"

mkdir -p "$WEBROOT"

if [ ! -d "$WEBROOT/.git" ]; then
  read -rp "Введите URL вашего Git-репозитория (https://github.com/USER/REPO.git): " REPO_URL
  if [ -z "$REPO_URL" ]; then
    echo "URL репозитория не может быть пустым."
    exit 1
  fi

  git clone "$REPO_URL" "$WEBROOT"
else
  cd "$WEBROOT"
  git pull
fi

chown -R www-data:www-data "$WEBROOT" 2>/dev/null || chown -R nginx:nginx "$WEBROOT" 2>/dev/null || true

if [ -d "/etc/nginx/sites-enabled" ]; then
  rm -f /etc/nginx/sites-enabled/default
fi

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${WEBROOT};
    index index.html;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

if [ -d "$(dirname "$NGINX_ENABLED")" ]; then
  ln -sf "$NGINX_CONF" "$NGINX_ENABLED"
fi

nginx -t
systemctl reload nginx

certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

systemctl reload nginx

echo "Установка завершена. Ваш сайт доступен по адресу: https://${DOMAIN}"

