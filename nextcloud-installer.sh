#!/bin/bash

# Mise à jour des paquets
sudo apt update
sudo apt upgrade -y

# Installation des dépendances nécessaires
sudo apt install -y lsb-release apt-transport-https ca-certificates software-properties-common wget

# Ajout du dépôt PHP
sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
sudo sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
sudo apt update

# Installation de PHP 8.3 et modules nécessaires
sudo apt install -y php8.3 php8.3-{bcmath,xml,fpm,mysql,zip,intl,ldap,gd,cli,bz2,curl,mbstring,pgsql,opcache,soap,cgi}

# Installation d'Apache et configuration pour PHP 8.3
sudo apt install -y apache2 libapache2-mod-php8.3

# Installation de MariaDB
sudo apt -y install mariadb-server mariadb-client

# Configuration sécurisée de MariaDB
sudo mysql_secure_installation

# Demande à l'utilisateur de saisir le nom d'utilisateur et le mot de passe de la base de données
read -p "Entrez le nom d'utilisateur pour la base de données Nextcloud: " dbuser
read -sp "Entrez le mot de passe pour la base de données Nextcloud: " dbpass
echo

# Configuration de la base de données pour Nextcloud
sudo mysql -u root -p <<MYSQL_SCRIPT
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
CREATE DATABASE ${dbuser};
GRANT ALL PRIVILEGES ON ${dbuser}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
QUIT
MYSQL_SCRIPT

echo "La base de données pour Nextcloud a été configurée."

# Demande du chemin du répertoire Nextcloud et du nom de serveur
read -p "Entrez le chemin complet du répertoire de Nextcloud (ex: /var/www/html/nextcloud): " nextcloud_path
read -p "Entrez le nom de serveur pour Nextcloud (ex: cloud.example.net): " server_name

# Configuration du VirtualHost Apache pour Nextcloud
echo "Voulez-vous configurer un VirtualHost pour Nextcloud en HTTP ou HTTPS (SSL) ? [HTTP/HTTPS]"
read -r server_protocol

if [ "$server_protocol" == "HTTPS" ]; then
    # Configuration pour HTTPS
    sudo bash -c 'cat > /etc/apache2/sites-available/nextcloud.conf' << EOF
<VirtualHost *:80>
    ServerName $server_name
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerAdmin admin@$server_name
    DocumentRoot $nextcloud_path
    ServerName $server_name
    <Directory $nextcloud_path>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        SetEnv HOME $nextcloud_path
        SetEnv HTTP_HOME $nextcloud_path
    </Directory>
    ErrorLog /var/log/apache2/nextcloud-error.log
    CustomLog /var/log/apache2/nextcloud-access.log combined
    SSLEngine on
    SSLCertificateFile /etc/ssl/nextcloud/fullchain.pem
    SSLCertificateKeyFile /etc/ssl/nextcloud/privkey.pem
</VirtualHost>
EOF
else
    # Configuration pour HTTP
    sudo bash -c 'cat > /etc/apache2/sites-available/nextcloud.conf' << EOF
<VirtualHost *:80>
    ServerAdmin admin@$server_name
    DocumentRoot $nextcloud_path
    ServerName $server_name
    <Directory $nextcloud_path>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/apache2/nextcloud-error.log
    CustomLog /var/log/apache2/nextcloud-access.log combined
</VirtualHost>
EOF
fi

# Activation du nouveau site et redémarrage d'Apache
sudo a2ensite nextcloud.conf
sudo systemctl restart apache2

# Installation des modules PHP supplémentaires pour Nextcloud
sudo apt-get install -y php-gmp php-bcmath php-imagick
sudo phpenmod gmp
sudo phpenmod bcmath
sudo phpenmod imagick

# Installation et configuration de Redis
sudo apt install -y redis-server php-redis
sudo systemctl restart redis-server

# Modification du fichier config.php de Nextcloud pour la configuration Redis
CONFIG_FILE="$nextcloud_path/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
    sudo sed -i "/);/i 'memcache.local' => '\\OC\\Memcache\\Redis'," $CONFIG_FILE
    grep -q "'memcache.locking'" $CONFIG_FILE || sudo sed -i "/);/i 'memcache.locking' => '\\OC\\Memcache\\Redis'," $CONFIG_FILE
    grep -q "'redis' =>" $CONFIG_FILE || {
        sudo sed -i "/);/i 'redis' => array(" $CONFIG_FILE
        sudo sed -i "/);/i 'host' => 'localhost'," $CONFIG_FILE
        sudo sed -i "/);/i 'port' => 6379," $CONFIG_FILE
        sudo sed -i "/);/i )," $CONFIG_FILE
    }
else
    echo "Le fichier config.php n'a pas été trouvé. Assurez-vous que Nextcloud est correctement installé et que le chemin est correct."
fi

echo "Nextcloud et toutes les dépendances ont été installés avec succès."
