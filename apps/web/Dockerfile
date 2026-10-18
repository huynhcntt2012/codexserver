# Admin portal: Next.js static export served under /admin.
FROM node:22-bookworm-slim AS admin
WORKDIR /src/apps/admin
ENV NEXT_TELEMETRY_DISABLED=1
COPY apps/admin/package.json apps/admin/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY apps/practice/assets/items /src/apps/practice/assets/items
COPY apps/practice/assets/bombs /src/apps/practice/assets/bombs
COPY apps/practice/assets/characters/portraits /src/apps/practice/assets/characters/portraits
COPY apps/practice/assets/ui/launch /src/apps/practice/assets/ui/launch
COPY apps/admin ./
RUN npm run build

FROM nginx:alpine@sha256:df221db836e1754089190208cee7eeda94f233197056426eda74a43ab1abeac2
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY apps/web/licenses /usr/share/licenses/suni-web
COPY apps/web/public /usr/share/nginx/html
COPY --from=admin /src/apps/admin/out /usr/share/nginx/html/admin
# Promotion website art comes straight from the game (docs/PORTAL.md).
COPY apps/practice/assets/characters/portraits /usr/share/nginx/html/assets/characters/portraits
COPY apps/practice/assets/level_previews /usr/share/nginx/html/assets/level_previews
COPY apps/practice/assets/items /usr/share/nginx/html/assets/items
COPY apps/practice/assets/ui/launch /usr/share/nginx/html/assets/ui/launch
EXPOSE 8080
