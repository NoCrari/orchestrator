FROM node:18-alpine

WORKDIR /app

# Install PostgreSQL client
RUN apk add --no-cache postgresql-client

# Copy package.json only
COPY package.json ./

# Install dependencies
RUN npm install --production && \
    npm cache clean --force

# Copy source code
COPY src/ ./src/

# Create non-root user and set permissions
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node src/healthcheck.js || exit 1

CMD ["node", "src/index.js"]