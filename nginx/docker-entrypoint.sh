#!/bin/sh
set -e

echo "Creating OpenResty runtime directories..."
mkdir -p /tmp/openresty/client_temp \
         /tmp/openresty/proxy_temp \
         /tmp/openresty/fastcgi_temp \
         /tmp/openresty/uwsgi_temp \
         /tmp/openresty/scgi_temp

echo "Verifying Nginx configuration directory contents..."
ls -la /usr/local/openresty/nginx/conf/

echo "Checking for mime.types file..."
if [ ! -f /usr/local/openresty/nginx/conf/mime.types ]; then
    echo "Warning: mime.types file not found"
fi

echo "What is in the godforsaken directory?!"
ls -la /usr/local/openresty/nginx/

echo "Contents of nginx.conf:"
cat /usr/local/openresty/nginx/conf/nginx.conf

echo "Testing nginx configuration..."
/usr/local/openresty/bin/openresty -t

echo "Starting OpenResty..."
exec "$@"