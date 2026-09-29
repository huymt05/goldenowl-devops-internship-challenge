FROM node:24-alpine AS dependencies

WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:24-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node src/package.json src/index.js ./
COPY --chown=node:node src/server ./server
COPY --chown=node:node src/routes ./routes

USER node
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD wget -q -O /dev/null http://127.0.0.1:3000/ || exit 1

CMD ["node", "index.js"]