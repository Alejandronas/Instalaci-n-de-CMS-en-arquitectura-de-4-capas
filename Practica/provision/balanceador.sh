#!/bin/bash

echo "=== Provisionando Balanceador de Carga Nginx ==="

# Actualizar maquina
apt-get update
apt-get upgrade -y

# Instalar nginx
apt-get install -y nginx

# Configurar nginx como balanceador de carga
# Los servidores web estan en la red 192.168.2.x


cat > /etc/nginx/sites-available/default <<'EOF'
upstream backend_servers {
    server 192.168.2.21:80;
    server 192.168.2.22:80;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://backend_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
      
    }

    access_log /var/log/nginx/balancer_access.log;
    error_log /var/log/nginx/balancer_error.log;
}
EOF

# Verificar configuracion y que este todo bien
nginx -t

# Reiniciar nginx
systemctl restart nginx
systemctl enable nginx

echo " Se ha hecho todo"