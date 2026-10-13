FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/arena/package.json apps/arena/package.json
RUN npm ci
COPY apps/arena apps/arena
RUN npm run build

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/arena/package.json apps/arena/package.json
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/apps/arena/dist apps/arena/dist
USER node
EXPOSE 2567
CMD ["node", "apps/arena/dist/index.js"]
