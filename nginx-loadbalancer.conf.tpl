worker_processes 1;

events {
    worker_connections 1024;
}

http {
    upstream backends {
        server ${NAME1}:55080;
        server ${NAME2}:55080;
        server ${NAME3}:55080;
    }

    server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;

        location / {
            proxy_pass http://backends;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
