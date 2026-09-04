# ---- Stage 1: Build Angular SPA ----
FROM node:24-alpine AS build

# Patch Alpine OS packages (fixes OpenSSL CVEs) and npm internal tools
RUN apk update && apk upgrade --no-cache && \
    npm install -g npm@latest

WORKDIR /app

# Copy only the descriptors first -> cache layer that is only invalidated
# when dependencies change, not on every code change
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline --no-audit --ignore-scripts

# Copy the rest of the code and compile.
COPY . .
RUN npm run build -- --configuration production

# ---- Stage 2: Nginx no-root, minimum, for serving static content ----
FROM nginxinc/nginx-unprivileged:stable-alpine-slim

# Copy the Angular build (owned by root so unprivileged nginx user cannot tamper with files)
COPY --from=build --chown=root:root /app/dist/frontend/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Defense in depth: explicit, even though the base image already runs as nginx.
USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
