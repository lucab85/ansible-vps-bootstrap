FROM node:20-alpine

WORKDIR /app
COPY . .
RUN --mount=type=cache,target=/root/.npm npm ci
# npm workspaces hoists a single React version for the whole monorepo; it picks
# React 19 (required by the Next.js storefront) at the repo root, but @medusajs/dashboard
# is ALSO hoisted to the repo root and expects React 18 there — it crashes at runtime
# with "Minified React error #31" if bundled against React 19. This backend image is a
# separate, isolated Docker build from the storefront's, so overriding the root React
# version here doesn't affect the storefront at all. See medusajs/medusa#15398.
RUN npm install --no-save react@18.3.1 react-dom@18.3.1
RUN npx turbo build --filter=@dtc/backend

WORKDIR /app/apps/backend/.medusa/server
RUN --mount=type=cache,target=/root/.npm npm install --omit=dev

ENV NODE_ENV=production
EXPOSE 9000
CMD ["sh", "-c", "npx medusa db:migrate && npx medusa db:sync-links && npm run start"]
