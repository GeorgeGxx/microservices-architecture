# Build stage
FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production runtime stage
FROM node:24-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8086

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist

USER node

EXPOSE 8086

HEALTHCHECK --interval=15s --timeout=3s --start-period=15s --retries=3 CMD ["wget", "-qO-", "http://127.0.0.1:8086/health"]

CMD ["node", "dist/main.js"]
