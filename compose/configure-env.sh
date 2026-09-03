#!/bin/bash
set -euo pipefail

source /opt/apps/.env

BACKEND_ENV=/opt/apps/medusa/.env

cat > "$BACKEND_ENV" <<EOF
NODE_ENV=production
DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/medusa
REDIS_URL=redis://redis:6379

STORE_CORS=${STOREFRONT_URL}
ADMIN_CORS=${MEDUSA_BACKEND_URL}
AUTH_CORS=${STOREFRONT_URL},${MEDUSA_BACKEND_URL}

JWT_SECRET=${JWT_SECRET}
COOKIE_SECRET=${COOKIE_SECRET}

MEDUSA_BACKEND_URL=${MEDUSA_BACKEND_URL}
EOF
chmod 600 "$BACKEND_ENV"

echo "Backend env file written."
