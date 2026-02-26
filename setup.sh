#!/bin/bash
# ============================================================
# Buy One Media LLC — seansandoval.com Server Setup
# Run as root on Hetzner: 178.156.209.250
# ============================================================
set -e

DOMAIN="seansandoval.com"
WEBROOT="/var/www/$DOMAIN"
REPO="https://github.com/BuyOneMedia/brycesite.git"
DEPLOY_SECRET="sean_deploy_74dba837941b880b0c994c18"
DEPLOY_SCRIPT="/usr/local/bin/deploy-seansandoval.sh"
WEBHOOK_PORT="9002"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   seansandoval.com — Server Setup    ║"
echo "╚══════════════════════════════════════╝"
echo ""

echo "▶ Setting up webroot at $WEBROOT..."
mkdir -p "$WEBROOT"

if [ -d "$WEBROOT/.git" ]; then
  cd "$WEBROOT" && git pull origin main
else
  git clone "$REPO" "$WEBROOT"
fi

chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"
echo "  ✓ Webroot ready"

echo ""
echo "▶ Creating deploy script..."
cat > "$DEPLOY_SCRIPT" << 'DEPLOY'
#!/bin/bash
cd /var/www/seansandoval.com
git pull origin main
chown -R www-data:www-data /var/www/seansandoval.com
echo "[$(date)] Deployed seansandoval.com" >> /var/log/seansandoval-deploy.log
DEPLOY
chmod +x "$DEPLOY_SCRIPT"
echo "  ✓ Deploy script at $DEPLOY_SCRIPT"

echo ""
echo "▶ Creating Nginx vhost..."
cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root $WEBROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /webhook-deploy {
        proxy_pass http://127.0.0.1:$WEBHOOK_PORT/hooks/deploy-seansandoval;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
nginx -t && systemctl reload nginx
echo "  ✓ Nginx vhost enabled"

echo ""
echo "▶ Adding webhook hook config..."
HOOKS_DIR="/etc/webhook"
mkdir -p "$HOOKS_DIR"

# Append to existing hooks.json or create new
if [ -f "$HOOKS_DIR/hooks.json" ]; then
  # Add new hook to existing array
  python3 -c "
import json
with open('/etc/webhook/hooks.json') as f:
    hooks = json.load(f)
new_hook = {
  'id': 'deploy-seansandoval',
  'execute-command': '/usr/local/bin/deploy-seansandoval.sh',
  'command-working-directory': '/var/www/seansandoval.com',
  'response-message': 'Deploying seansandoval.com...',
  'trigger-rule': {
    'match': {
      'type': 'payload-hash-sha1',
      'secret': 'sean_deploy_74dba837941b880b0c994c18',
      'parameter': {'source': 'header', 'name': 'X-Hub-Signature'}
    }
  }
}
if not any(h['id'] == 'deploy-seansandoval' for h in hooks):
    hooks.append(new_hook)
with open('/etc/webhook/hooks.json', 'w') as f:
    json.dump(hooks, f, indent=2)
print('  Hook added to existing hooks.json')
"
else
  cat > "$HOOKS_DIR/hooks.json" << EOF
[
  {
    "id": "deploy-seansandoval",
    "execute-command": "$DEPLOY_SCRIPT",
    "command-working-directory": "$WEBROOT",
    "response-message": "Deploying seansandoval.com...",
    "trigger-rule": {
      "match": {
        "type": "payload-hash-sha1",
        "secret": "$DEPLOY_SECRET",
        "parameter": {"source": "header", "name": "X-Hub-Signature"}
      }
    }
  }
]
EOF
fi

# Restart webhook service (it already exists from buyonemedia setup)
systemctl restart webhook-buyonemedia 2>/dev/null || true
echo "  ✓ Webhook hook registered on port $WEBHOOK_PORT"

echo ""
echo "▶ Installing SSL..."
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email hello@buyonemedia.com --redirect   && echo "  ✓ SSL installed"   || echo "  ⚠ SSL failed — run: certbot --nginx -d $DOMAIN (after DNS propagates)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  seansandoval.com SETUP COMPLETE                 ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  Webroot:  /var/www/seansandoval.com                 ║"
echo "║  Repo:     github.com/BuyOneMedia/brycesite          ║"
echo "║                                                      ║"
echo "║  ── ADD GITHUB WEBHOOK ──                            ║"
echo "║  Repo: BuyOneMedia/brycesite → Settings → Webhooks  ║"
echo "║  Payload URL:                                        ║"
echo "║  http://178.156.209.250/webhook-deploy               ║"
printf "║  Secret: %-43s║\n" "sean_deploy_74dba837941b880b0c994c18"
echo "║  Content-type: application/json                      ║"
echo "║                                                      ║"
echo "║  ── DNS (add at your registrar) ──                   ║"
echo "║  A  @    178.156.209.250                             ║"
echo "║  A  www  178.156.209.250                             ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
