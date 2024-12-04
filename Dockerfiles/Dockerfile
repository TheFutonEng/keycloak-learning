# Use OpenResty as base image
FROM openresty/openresty:alpine

# Install required packages for building and running
RUN apk add --no-cache \
    git \
    gcc \
    musl-dev \
    make \
    curl \
    pcre-dev \
    openssl-dev \
    zlib-dev \
    luarocks5.3 \
    lua5.3-dev

# Configure luarocks to use the correct Lua version
RUN ln -s /usr/bin/luarocks-5.3 /usr/local/bin/luarocks

# Install lua-resty-openidc and its dependencies
RUN luarocks install lua-cjson && \
    luarocks install lua-resty-string && \
    luarocks install lua-resty-http && \
    luarocks install lua-resty-jwt && \
    luarocks install lua-resty-session && \
    luarocks install lua-resty-openidc

# Create necessary directories with correct permissions
RUN mkdir -p /var/log/nginx /var/cache/nginx /var/run && \
    mkdir -p /tmp/nginx/client_temp && \
    mkdir -p /tmp/nginx/proxy_temp && \
    mkdir -p /tmp/nginx/fastcgi_temp && \
    mkdir -p /tmp/nginx/uwsgi_temp && \
    mkdir -p /tmp/nginx/scgi_temp && \
    mkdir -p /usr/local/openresty/nginx/conf && \
    chown -R nobody:nobody /var/log/nginx /var/cache/nginx /var/run /tmp/nginx /usr/local/openresty/nginx/conf && \
    chmod -R 755 /tmp/nginx /usr/local/openresty/nginx/conf

# Create a test page
RUN mkdir -p /usr/share/nginx/html && \
    chown -R nobody:nobody /usr/share/nginx/html && \
    echo '<html><body><h1>Protected Page</h1><pre id="userinfo">Loading user info...</pre><script>fetch("/debug").then(r=>r.json()).then(data=>document.getElementById("userinfo").textContent=JSON.stringify(data,null,2));</script></body></html>' > /usr/share/nginx/html/index.html

# Use non-root user
USER nobody

# OpenResty's default entry point will handle nginx with explicit config path
CMD ["/usr/local/openresty/bin/openresty", "-c", "/usr/local/openresty/nginx/conf/nginx.conf", "-g", "daemon off;"]