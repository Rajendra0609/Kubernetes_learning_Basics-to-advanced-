# ============================================================
# Multi-stage Dockerfile — Node.js API
# Best practices: minimal final image, non-root, no dev deps
# ============================================================

# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
# Copy only dependency manifests first (layer caching)
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force
COPY . .
RUN npm run build 2>/dev/null || true   # TypeScript compile if applicable

# Stage 2: Production image
FROM node:20-alpine AS production
# Security: create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser  -u 1001 -S nodejs -G nodejs

WORKDIR /app

# Copy only production artifacts
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/package.json .

# Security hardening
USER nodejs
EXPOSE 3000
ENV NODE_ENV=production

# Health check built into container
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/healthz', r => process.exit(r.statusCode===200?0:1))"

CMD ["node", "dist/server.js"]
