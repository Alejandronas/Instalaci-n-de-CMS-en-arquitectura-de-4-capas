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
echo ""
echo "PHP-FPM escuchando en:"
netstat -tulpn | grep 9000

ls -lh /var/nfs/shared/index.php