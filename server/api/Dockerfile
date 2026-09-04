FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN time npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
RUN time npm run build
RUN time npm prune --omit=dev --no-audit --no-fund

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
RUN apk add --no-cache postgresql-client
COPY --from=build /app/package.json /app/package-lock.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY migrations ./migrations
COPY scripts ./scripts
RUN chmod +x ./scripts/migrate.sh
USER node
EXPOSE 3000
CMD ["npm", "start"]
