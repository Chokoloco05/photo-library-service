# syntax=docker/dockerfile:1
FROM node:24-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM node:24-alpine AS runtime
ARG APP_REVISION=local
ENV NODE_ENV=production
ENV PORT=3000
ENV APP_REVISION=${APP_REVISION}
LABEL org.opencontainers.image.revision=${APP_REVISION}
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json app.js auth.js identity.js server.js database.js photos.js migrate.js metrics.js cache.js ./
COPY --chown=node:node public ./public
COPY --chown=node:node migrations ./migrations
USER node
EXPOSE 3000
EXPOSE 9090
CMD ["node", "server.js"]
