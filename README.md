# Despliegue de Aplicación LEMP en 4 capas

## 1. Descripción general

Este proyecto consiste en el despliegue local de una aplicación web de Gestión de Usuarios sobre una infraestructura en alta disponibilidad, organizada en cuatro capas, utilizando una pila LEMP (Linux, Nginx, MariaDB y PHP).

La infraestructura se despliega utilizando Vagrant , con máquinas basadas en Debian . El aprovisionamiento de todas las máquinas se realiza mediante scripts automatizados, minimizando la configuración manual.

---

## 2. Arquitectura de la infraestructura

La infraestructura está dividida en cuatro capas claramente diferenciadas, comunicadas mediante **redes privadas independientes**, cada una con su propio rango de direcciones IP.

---

## 3. Esquema de red y rangos de IP

| Red | Rango IP | Uso |
|----|---------|-----|
| Acceso público | 192.168.10.0/24 | Acceso cliente al balanceador |
| Red Backend | 192.168.2.0/24 | Balanceador ↔ Servidores Web |
| Red Aplicación | 192.168.3.0/24 | Servidores Web ↔ NFS  |
| Red Lógica Aplicación-BD | 192.168.4.0/24 | NFS  ↔ Proxy BD|
| Red Base de Datos | 192.168.5.0/24 | Proxy BD ↔ MariaDB |

Las capas 2, 3 y 4 no están expuestas a red pública.

---

## 4. Capa 1 – Balanceador de carga (red pública)

**Máquina**
- balanceadorAlejandro

**Servicios**
- Nginx

**Interfaces de red**
- 192.168.10.10 → Red pública / Balanceador
- 192.168.2.10 → Red Web
### Aprovisionamiento
```bash
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

```

## 5. Capa 2 – WEB 

### Servidores Web

#### serverweb1Alejandro

**Interfaces de red**
- 192.168.2.21 → Comunicación con el balanceador
- 192.168.3.21 → Comunicación con NFS

#### serverweb2Alejandro

**Interfaces de red**
- 192.168.2.22 → Comunicación con el balanceador
- 192.168.3.22 → Comunicación con NFS

**Servicios**
- Nginx

```bash
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
    #Si no ha habido exito lo reintenta
    echo "Intento $i/30..."
    sleep 2
done

# Montar NFS
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
```

## 6. Servidor NFS 

**Máquina**
- serverNFSAlejandro

**Interfaces de red**
- 192.168.3.23 → Comunicación con servidores web
- 192.168.4.23 → Comunicación con proxy de base de datos

**Servicios**
- NFS Server
- PHP-FPM
```bash
#!/bin/bash

# Actualizar la maquina
apt-get update
apt-get upgrade -y

# Instalar NFS y las extensiones necesarias 
apt-get install -y nfs-kernel-server php-fpm php-mysql php-cli php-common php-mbstring php-xml php-zip php-curl

# Crear directorio compartido
mkdir -p /var/nfs/shared
chown -R www-data:www-data /var/nfs/shared
chmod -R 755 /var/nfs/shared

# Configurar exports de NFS para servidores web en la red 192.168.3.x
cat > /etc/exports <<'EOF'
/var/nfs/shared 192.168.3.21(rw,sync,no_subtree_check,no_root_squash)
/var/nfs/shared 192.168.3.22(rw,sync,no_subtree_check,no_root_squash)
EOF

# Aplicar configuracion NFS
exportfs -a
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

# Configurar PHP para escuchar en red
# Variables creadas porque aveces se instala una version diferente y para asegurarnos que version es
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

# Backup de configuracion original usando las variables
cp $PHP_FPM_CONF ${PHP_FPM_CONF}.backup

# Configuracion de PHP para escuchar en todas las interfaces
sed -i 's/listen = .*/listen = 0.0.0.0:9000/' $PHP_FPM_CONF
sed -i 's/;listen.allowed_clients/listen.allowed_clients/' $PHP_FPM_CONF
sed -i 's/listen.allowed_clients = .*/listen.allowed_clients = 192.168.3.21,192.168.3.22/' $PHP_FPM_CONF

# Reiniciar PHP
systemctl restart php${PHP_VERSION}-fpm
systemctl enable php${PHP_VERSION}-fpm

# Crear aplicacion de gestion de usuarios
cat > /var/nfs/shared/index.php <<'PHPEOF'
<?php
session_start();

// Configuracion de base de datos - Conecta a traves de HAProxy en red 192.168.4.x
$db_host = '192.168.4.30';
$db_user = 'appuser';
$db_pass = 'apppass123';
$db_name = 'gestion_usuarios';

// Conectar a la base de datos
try {
    $pdo = new PDO("mysql:host=$db_host;dbname=$db_name;charset=utf8mb4", $db_user, $db_pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    die("Error de conexion: " . $e->getMessage());
}

// Procesar formularios
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    if (isset($_POST['action'])) {
        switch ($_POST['action']) {
            case 'add':
                $nombre = $_POST['nombre'];
                $email = $_POST['email'];
                $telefono = $_POST['telefono'];
                
                $stmt = $pdo->prepare("INSERT INTO usuarios (nombre, email, telefono) VALUES (?, ?, ?)");
                $stmt->execute([$nombre, $email, $telefono]);
                $_SESSION['message'] = "Usuario agregado correctamente";
                break;
                
            case 'delete':
                $id = $_POST['id'];
                $stmt = $pdo->prepare("DELETE FROM usuarios WHERE id = ?");
                $stmt->execute([$id]);
                $_SESSION['message'] = "Usuario eliminado correctamente";
                break;
                
            case 'update':
                $id = $_POST['id'];
                $nombre = $_POST['nombre'];
                $email = $_POST['email'];
                $telefono = $_POST['telefono'];
                
                $stmt = $pdo->prepare("UPDATE usuarios SET nombre = ?, email = ?, telefono = ? WHERE id = ?");
                $stmt->execute([$nombre, $email, $telefono, $id]);
                $_SESSION['message'] = "Usuario actualizado correctamente";
                break;
        }
        header("Location: index.php");
        exit();
    }
}

// Obtener lista de usuarios
$stmt = $pdo->query("SELECT * FROM usuarios ORDER BY id DESC");
$usuarios = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Obtener informacion del servidor
$hostname = gethostname();
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gestión de Usuarios - LEMP HA</title>
    
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Gestion de Usuarios</h1>
            <p>Infraestructura LEMP</p>
            <div class="server-info">
                <strong>Servidor:</strong> <?php echo $hostname; ?> | 
                <strong>IP Cliente:</strong> <?php echo $_SERVER['REMOTE_ADDR']; ?>
            </div>
        </div>
        
        <?php if (isset($_SESSION['message'])): ?>
            <div class="message">
                <?php echo $_SESSION['message']; unset($_SESSION['message']); ?>
            </div>
        <?php endif; ?>
        
        <div class="card">
            <h2> Agregar Nuevo Usuario</h2>
            <form method="POST" action="">
                <input type="hidden" name="action" value="add">
                <div class="form-group">
                    <label>Nombre Completo:</label>
                    <input type="text" name="nombre" required>
                </div>
                <div class="form-group">
                    <label>Email:</label>
                    <input type="email" name="email" required>
                </div>
                <div class="form-group">
                    <label>Numero de Telefono:</label>
                    <input type="text" name="telefono" required>
                </div>
                <button type="submit" class="btn btn-primary">Agregar Usuario</button>
            </form>
        </div>
        
        <div class="card">
            <h2> Lista de Usuarios</h2>
            <?php if (count($usuarios) > 0): ?>
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Nombre</th>
                            <th>Email</th>
                            <th>Teléfono</th>
                            <th>Acciones</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($usuarios as $usuario): ?>
                        <tr>
                            <td><?php echo htmlspecialchars($usuario['id']); ?></td>
                            <td><?php echo htmlspecialchars($usuario['nombre']); ?></td>
                            <td><?php echo htmlspecialchars($usuario['email']); ?></td>
                            <td><?php echo htmlspecialchars($usuario['telefono']); ?></td>
                            <td>
                                <div class="actions">
                                    <button class="btn btn-warning" onclick="editUser(<?php echo htmlspecialchars(json_encode($usuario)); ?>)">Editar</button>
                                    <form method="POST" style="display:inline;" onsubmit="return confirm('¿Eliminar este usuario?');">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="id" value="<?php echo $usuario['id']; ?>">
                                        <button type="submit" class="btn btn-danger">Eliminar</button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php else: ?>
                <p style="text-align:center; color:#999; margin-top:20px;">No hay usuarios registrados.</p>
            <?php endif; ?>
        </div>
    </div>
    
    <div id="editModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h2> Editar Usuario</h2>
                <span class="close" onclick="closeModal()">&times;</span>
            </div>
            <form method="POST" action="">
                <input type="hidden" name="action" value="update">
                <input type="hidden" name="id" id="edit_id">
                <div class="form-group">
                    <label>Nombre Completo:</label>
                    <input type="text" name="nombre" id="edit_nombre" required>
                </div>
                <div class="form-group">
                    <label>Email:</label>
                    <input type="email" name="email" id="edit_email" required>
                </div>
                <div class="form-group">
                    <label>Teléfono:</label>
                    <input type="text" name="telefono" id="edit_telefono" required>
                </div>
                <button type="submit" class="btn btn-primary">Actualizar Usuario</button>
            </form>
        </div>
    </div>
    
    <script>
        function editUser(user) {
            document.getElementById('edit_id').value = user.id;
            document.getElementById('edit_nombre').value = user.nombre;
            document.getElementById('edit_email').value = user.email;
            document.getElementById('edit_telefono').value = user.telefono;
            document.getElementById('editModal').style.display = 'flex';
        }
        function closeModal() {
            document.getElementById('editModal').style.display = 'none';
        }
        window.onclick = function(event) {
            const modal = document.getElementById('editModal');
            if (event.target == modal) closeModal();
        }
    </script>
</body>
</html>
PHPEOF

# Establecer permisos correctos
chown -R www-data:www-data /var/nfs/shared
chmod -R 755 /var/nfs/shared
chmod 644 /var/nfs/shared/index.php


exportfs -v
echo "PHP escuchando en:"
netstat -tulpn | grep 9000

```
---

## 7. Capa 3 – Proxy de Base de Datos

**Máquina**
- proxyBBDDAlejandro

**Interfaces de red**
- 192.168.4.30 → Comunicación con la aplicación
- 192.168.5.30 → Comunicación con la base de datos

**Servicio**
- HAProxy
```bash
#!/bin/bash

# Actualizar maquina
apt-get update
apt-get upgrade -y

# Instalar haProxy
apt-get install -y haproxy

# Configurar haproxy para MariaDB
cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

listen mysql-cluster
    bind *:3306
    mode tcp
    option mysql-check user haproxy
    balance roundrobin
    # Base de datos en red 192.168.5.x
    server mariadb1 192.168.5.40:3306 check

listen stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats realm HAProxy\ Statistics
    stats auth admin:admin123
EOF

# Verificar configuracion
haproxy -c -f /etc/haproxy/haproxy.cfg

# Habilitar y arrancar haproxy
systemctl enable haproxy
systemctl restart haproxy

```
---

## 8. Capa 4 – Base de Datos

**Máquina**
- serverdatosAlejandro

**Interfaz de red**
- 192.168.5.40 → Red de base de datos

**Servicio**
- MariaDB

```bash

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

```

---


