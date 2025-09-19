global
    log stdout format raw local0
    maxconn 1024
    tune.ssl.default-dh-param 2048

defaults
    log     global
    mode    http
    option  httplog
    option  dontlog-normal
    option  http-server-close
    timeout connect 10s
    timeout client  50s
    timeout server  300s
    timeout check   10s
    retries 3

# Redirect HTTP -> HTTPS (port 8080)
frontend http_redirect
    bind *:8080
    mode http
    redirect scheme https code 301 if !{ ssl_fc }

# Frontend for Harbor (HTTPS termination)
frontend harbor_frontend
    bind *:8443 ssl crt /usr/local/etc/haproxy/haproxy.pem
    mode http

    # Add headers so Harbor knows the original request was HTTPS
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Port 8443 if { ssl_fc }

    # Security headers
    http-response add-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    http-response replace-header Set-Cookie ^(.*)$ "\1; Secure" if { ssl_fc }

    default_backend harbor_backends

# Backend pool of Harbor nodes with sticky sessions
backend harbor_backends
    mode http
    balance roundrobin
    cookie SERVERID insert indirect nocache

    # Enable health checks
    option httpchk
    http-check send meth GET uri /api/v2.0/health ver HTTP/1.1 hdr Host sit.xxx.com

    # Forward headers to backend
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Port 8443 if { ssl_fc }

    # Server defaults
    default-server inter 2s fall 3 rise 5

    # Backend servers
    server harbor1 ${NAME1}:55080 check cookie harbor1
    server harbor2 ${NAME2}:55080 check cookie harbor2
    server harbor3 ${NAME3}:55080 check cookie harbor3

# HAProxy Stats GUI
frontend haproxy_stats
    bind *:7000
    mode http
    option http-keep-alive
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats show-node
    stats auth admin:admin

