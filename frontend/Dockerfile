# Frontend Dockerfile - React + Vite with hot reload for development
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files first for better layer caching
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
# Note: In development, this will be overridden by volume mount for hot reload
COPY . .

# Expose Vite dev server port
EXPOSE 5173

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:5173 || exit 1

# Run Vite dev server
# npm install ensures node_modules is populated when the anonymous volume is empty (fresh install)
# --host 0.0.0.0 is required for Docker networking to work
CMD ["sh", "-c", "npm install && npm run dev -- --host 0.0.0.0"]
