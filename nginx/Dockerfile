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

# Create necessary directories and set permissions
RUN mkdir -p /var/run/openresty \
    /var/log/openresty \
    /var/cache/openresty \
    /tmp/openresty \
    /usr/local/openresty/nginx/conf \
    /usr/share/nginx/html \
    /usr/local/openresty/nginx/logs && \
    chown -R nobody:nobody \
    /var/run/openresty \
    /var/log/openresty \
    /var/cache/openresty \
    /tmp/openresty \
    /usr/local/openresty/nginx/conf \
    /usr/share/nginx/html \
    /usr/local/openresty/nginx/logs \
    /usr/local/openresty/nginx

# Create test page
RUN echo '<html><body><h1>Protected Page</h1><pre id="userinfo">Loading user info...</pre><script>fetch("/debug").then(r=>r.json()).then(data=>document.getElementById("userinfo").textContent=JSON.stringify(data,null,2));</script></body></html>' > /usr/share/nginx/html/index.html

# Copy and prepare entrypoint script (do this before switching to nobody user)
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh && \
    chown nobody:nobody /docker-entrypoint.sh

# Switch to non-root user
USER nobody

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-c", "/usr/local/openresty/nginx/conf/nginx.conf"]