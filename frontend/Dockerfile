# ---- Stage 1: Build React 19 SPA with Vite ----
FROM node:22-alpine AS build

WORKDIR /app

# Copy package manifests first for optimal Docker layer caching
COPY package*.json ./
RUN npm ci --prefer-offline --no-audit

# Copy source and build
COPY . .
RUN npm run build

# ---- Stage 2: Distroless Nginx minimal non-root runtime ----
FROM cgr.dev/chainguard/nginx:latest

# Copy the Vite production bundle (owned by root with read/execute permissions for non-root runtime)
COPY --from=build --chown=root:root --chmod=755 /app/dist /usr/share/nginx/html
COPY rate-limit.conf /etc/nginx/conf.d/00-rate-limit.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.default.conf

USER 65532

EXPOSE 8080

CMD ["-e", "/dev/stderr", "-g", "daemon off;"]
