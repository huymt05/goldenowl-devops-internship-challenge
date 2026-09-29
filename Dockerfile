FROM node:24-alpine AS dependencies

WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM gcr.io/distroless/nodejs24-debian13:nonroot

ENV NODE_ENV=production
WORKDIR /app

COPY --from=dependencies --chown=65532:65532 /app/node_modules ./node_modules
COPY --chown=65532:65532 src/index.js ./
COPY --chown=65532:65532 src/server ./server
COPY --chown=65532:65532 src/routes ./routes

USER 65532:65532
EXPOSE 3000
CMD ["index.js"]