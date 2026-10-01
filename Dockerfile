FROM node:24-alpine AS dependencies

WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:24-alpine AS runtime

ENV NODE_ENV=production
WORKDIR /app

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node src/index.js ./
COPY --chown=node:node src/server ./server
COPY --chown=node:node src/routes ./routes

USER node
EXPOSE 3000
CMD ["node", "index.js"]