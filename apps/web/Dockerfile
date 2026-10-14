FROM nginx:alpine@sha256:df221db836e1754089190208cee7eeda94f233197056426eda74a43ab1abeac2
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY apps/web/licenses /usr/share/licenses/suni-web
COPY apps/web/public /usr/share/nginx/html
EXPOSE 8080
