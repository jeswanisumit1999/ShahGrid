# Pre-built Flutter web output is copied in at build time.
# Run: flutter build web --release --dart-define=API_BASE_URL=<url>
# before building this image.
FROM nginx:alpine

COPY build/web /usr/share/nginx/html

# SPA fallback: all routes serve index.html
RUN printf 'server {\n  listen 80;\n  root /usr/share/nginx/html;\n  index index.html;\n  location / { try_files $uri $uri/ /index.html; }\n}\n' \
    > /etc/nginx/conf.d/default.conf

EXPOSE 80
