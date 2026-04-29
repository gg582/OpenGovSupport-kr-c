#!/bin/sh
# Generates /etc/nginx/conf.d/default.conf at startup based on whether TLS
# certificates are present, then execs nginx.
#
# HTTPS mode  : drop fullchain.pem + privkey.pem into ./nginx/certs/ and set
#               PUBLIC_DOMAIN in .env before running `make compose-up-proxy`.
# HTTP mode   : start without certificates — nginx serves plain HTTP only.
set -e

CERT=/etc/nginx/certs/fullchain.pem
KEY=/etc/nginx/certs/privkey.pem
CONF=/etc/nginx/conf.d/default.conf
DOMAIN="${PUBLIC_DOMAIN:-_}"

# Common proxy location blocks shared by both HTTP and HTTPS server contexts.
proxy_locations() {
    cat << 'EOF'
    client_max_body_size 25m;

    location /healthz {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location /api/ {
        proxy_pass         http://backend:8080/api/;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    location / {
        proxy_pass         http://frontend:3000/;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
EOF
}

if [ -f "$CERT" ] && [ -f "$KEY" ]; then
    echo "[nginx-entrypoint] certificates found — starting in HTTPS mode (domain: ${DOMAIN})"
    {
        printf 'server {\n    listen 80;\n    server_name %s;\n    return 301 https://%s$request_uri;\n}\n\n' \
            "${DOMAIN}" "${DOMAIN}"
        printf 'server {\n    listen 443 ssl http2;\n    server_name %s;\n\n' "${DOMAIN}"
        cat << 'EOF'
    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

EOF
        proxy_locations
        echo "}"
    } > "$CONF"
else
    echo "[nginx-entrypoint] no certificates found — starting in HTTP-only mode"
    {
        printf 'server {\n    listen 80;\n    server_name %s;\n\n' "${DOMAIN}"
        proxy_locations
        echo "}"
    } > "$CONF"
fi

exec nginx -g 'daemon off;'
