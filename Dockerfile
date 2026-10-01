ARG ALPINE_VERSION=3.24

FROM node:24-alpine${ALPINE_VERSION} AS dependencies
WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM alpine:${ALPINE_VERSION} AS runtime
RUN apk add --no-cache libstdc++ dumb-init \
    && addgroup -g 1000 node \
    && adduser -u 1000 -G node -s /bin/sh -D node

ENV NODE_ENV=production
WORKDIR /app

COPY --from=dependencies /usr/local/bin/node /usr/local/bin/node
COPY --from=dependencies --chown=1000:1000 /app/node_modules ./node_modules
COPY --chown=1000:1000 src/index.js ./
COPY --chown=1000:1000 src/server ./server
COPY --chown=1000:1000 src/routes ./routes

USER 1000:1000
EXPOSE 3000
CMD ["dumb-init", "node", "index.js"]