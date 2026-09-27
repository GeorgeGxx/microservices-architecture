# ---- Stage 1: Build React 19 SPA with Vite ----
FROM node:22-alpine AS build

RUN apk update && apk upgrade --no-cache && \
    npm install -g npm@latest

WORKDIR /app

# Copy package manifests first for optimal Docker layer caching
COPY package*.json ./
RUN npm ci --prefer-offline --no-audit

# Copy source and build
COPY . .
RUN npm run build

# ---- Stage 2: Nginx unprivileged minimal runtime ----
FROM nginxinc/nginx-unprivileged:stable-alpine-slim

# Copy the Vite production bundle
COPY --from=build --chown=root:root /app/dist /usr/share/nginx/html
COPY rate-limit.conf /etc/nginx/conf.d/00-rate-limit.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
