#!/bin/bash



# Actualizar el sistema
apt-get update
apt-get upgrade -y

# Instalar Mariadb
# Debian FrontEND se usa para no tener que usar la interfaz grafica y poder hacerlo mediantes sripts
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server

# Configurar MariaDB para escuchar en todas las interfaces
cat > /etc/mysql/mariadb.conf.d/60-server.cnf <<'EOF'
[server]
[mysqld]
bind-address = 0.0.0.0
max_connections = 200

[embedded]
[mariadb]
[mariadb-10.5]
EOF

# Reiniciar MariaDB
systemctl restart mariadb
systemctl enable mariadb

# Usamos el comando sleep para que vaya iniciandoy no de errores al crear la base de datos

sleep 5

# Crear base de datos y usuario
mysql -u root <<'MYSQLEOF'
-- Crear base de datos
CREATE DATABASE IF NOT EXISTS gestion_usuarios CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Crear usuario de aplicacion con acceso desde cualquier IP
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'apppass123';
GRANT ALL PRIVILEGES ON gestion_usuarios.* TO 'appuser'@'%';

-- Crear usuario para HAProxy health checks
CREATE USER IF NOT EXISTS 'haproxy'@'%';
GRANT USAGE ON *.* TO 'haproxy'@'%';

-- Usar la base de datos
USE gestion_usuarios;

-- Crear tabla de usuarios
CREATE TABLE IF NOT EXISTS usuarios (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    telefono VARCHAR(20),
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insertar datos de ejemplo
INSERT INTO usuarios (nombre, email, telefono) VALUES
('Juan Perez', 'juan.perez@gmail.com', '+34 600 123 456'),
('Maria García', 'maria.garcia@gmail.com', '+34 600 234 567'),
('Carlos Rodríguez', 'carlos.rodriguez@gmail.com', '+34 600 345 678'),
('Ana Martínez', 'ana.martinez@gmail.com', '+34 600 456 789'),
('Luis Sánchez', 'luis.sanchez@gmaiñ.com', '+34 600 567 890')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

-- Aplicar cambios
FLUSH PRIVILEGES;
MYSQLEOF




mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User IN ('appuser', 'haproxy');"
mysql -u root -e "USE gestion_usuarios; SHOW TABLES;"