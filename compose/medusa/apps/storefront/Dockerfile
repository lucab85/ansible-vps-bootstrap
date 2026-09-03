FROM node:20-alpine

WORKDIR /app
COPY . .
RUN --mount=type=cache,target=/root/.npm npm ci
RUN npx turbo build --filter=@dtc/storefront

WORKDIR /app/apps/storefront
ENV NODE_ENV=production
EXPOSE 8000
CMD ["npm", "run", "start"]
