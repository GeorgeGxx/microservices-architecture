ARG NODE_VERSION=24.15-alpine

# Build stage
FROM node:${NODE_VERSION} AS builder

WORKDIR /app

RUN apk upgrade --no-cache && npm install --global npm@12.2.1

COPY package*.json ./
COPY scripts/patch-kafkajs-request-queue.mjs ./scripts/
RUN npm ci

COPY . .
RUN npm run build

# Production runtime stage
FROM node:${NODE_VERSION} AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8086

COPY package*.json ./
COPY scripts/patch-kafkajs-request-queue.mjs ./scripts/
RUN apk upgrade --no-cache \
    && npm install --global npm@12.2.1 \
    && npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /root/.npm

COPY --from=builder /app/dist ./dist

USER node

EXPOSE 8086

HEALTHCHECK --interval=15s --timeout=3s --start-period=15s --retries=3 CMD ["wget", "-qO-", "http://127.0.0.1:8086/health"]

CMD ["node", "dist/main.js"]
