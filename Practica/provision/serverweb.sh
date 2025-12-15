#!/bin/bash

# Actualizar el equipo
apt-get update
apt-get upgrade -y

# Instalar nginx y cliente NFS
apt-get install -y nginx nfs-common

# Crear directorio para montar NFS
mkdir -p /var/www/html
chown www-data:www-data /var/www/html

# Configurar montaje NFS con opcion _netdev
echo "192.168.3.23:/var/nfs/shared /var/www/html nfs defaults,_netdev 0 0" >> /etc/fstab

# Esperar a que el servidor nfs este disponible bucle for para ver si se monta, si no se monta da error en el resto de maquinas
echo "Esperando servidor NFS..."
for i in {1..30}; do
    if showmount -e 192.168.3.23 >/dev/null 2>&1; then
        echo "Servidor nfs detectado!"
        break
    fi
    #Si no ha habido exito lo reinitena
    echo "Intento $i/30..."
    sleep 2
done

# Montar ns
mount -a

# Configurar Nginx para usar PHP
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        
        # PHP-FPM remoto en red 192.168.3.x
        fastcgi_pass 192.168.3.23:9000;
        
        # CRITICO: Traducir ruta para PHP-FPM remoto
        # Servidor web monta NFS en: /var/www/html
        # PHP-FPM tiene los archivos en: /var/nfs/shared
        fastcgi_param SCRIPT_FILENAME /var/nfs/shared$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT /var/nfs/shared;
        
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    access_log /var/log/nginx/app_access.log;
    error_log /var/log/nginx/app_error.log;
}
EOF

# Verificar configuracion
nginx -t

# Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx
