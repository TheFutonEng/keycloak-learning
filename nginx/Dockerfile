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
    lua5.1-dev \
    luarocks \
    zlib \
    zlib-static \
    linux-headers

RUN ln -sf /usr/bin/luarocks-5.1 /usr/bin/luarocks

# Debug luarocks installation
RUN which luarocks || echo "luarocks not in PATH" && \
    ls -la /usr/bin/luarocks || echo "luarocks not in /usr/bin" && \
    ls -la /sbin/luarocks || echo "luarocks not in /sbin" && \
    find / -name luarocks 2>/dev/null || echo "luarocks not found anywhere"

# Install lua-resty-openidc and its dependencies
RUN luarocks install lua-cjson && \
    luarocks install lua-resty-string && \
    luarocks install lua-resty-http && \
    luarocks install lua-resty-jwt && \
    luarocks install lua-resty-session && \
    luarocks install lua-resty-openidc && \
    luarocks install lua-ffi-zlib

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

RUN mkdir -p /usr/local/openresty/lualib/resty && \
    ln -sf /usr/local/share/lua/5.1/resty/openidc.lua /usr/local/openresty/lualib/resty/openidc.lua && \
    ln -sf /usr/local/share/lua/5.1/resty/jwt.lua /usr/local/openresty/lualib/resty/jwt.lua && \
    ln -sf /usr/local/share/lua/5.1/resty/session.lua /usr/local/openresty/lualib/resty/session.lua

RUN ln -sf /usr/local/share/lua/5.1/resty/* /usr/local/openresty/lualib/resty/

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