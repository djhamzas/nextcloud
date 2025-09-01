sudo apt install apache2 mariadb-server libapache2-mod-php \
php-gd php-mysql php-curl php-xml php-zip php-mbstring php-intl php-bcmath unzip wget -y
#
sudo a2enmod rewrite headers env dir mime
# mysql installation
sudo mysql -e "DELETE FROM mysql.user WHERE User=''; \
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); \
DROP DATABASE IF EXISTS test; \
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; \
FLUSH PRIVILEGES;"

# config mysal databse
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'MyRootPass123';"
mysql -u root -pMyRootPass123 -e "CREATE DATABASE nextcloud;"
mysql -u root -pMyRootPass123 -e "CREATE USER 'nextclouduser'@'localhost' IDENTIFIED BY 'nextpassword';"
mysql -u root -pMyRootPass123 -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextclouduser'@'localhost';"
mysql -u root -pMyRootPass123 -e "FLUSH PRIVILEGES;"
# Download Nextcloud with verification
cd /var/www && wget https://download.nextcloud.com/server/releases/latest.zip
# Wait and verify download completed successfully
if [ ! -f "/var/www/latest.zip" ] || [ ! -s "/var/www/latest.zip" ]; then
    echo "Error: Nextcloud download failed or file is empty"
    exit 1
fi
echo "Nextcloud download completed successfully"
# Unzip Nextcloud
cd /var/www && unzip latest.zip
# Move Nextcloud to Apache root
mv /var/www/nextcloud /var/www/html/
# Fix permissions
chown -R www-data:www-data /var/www/html/nextcloud
chmod -R 755 /var/www/html/nextcloud
# Apache vhost
# Create Apache config for Nextcloud
cat > /etc/apache2/sites-available/nextcloud.conf <<'EOF'
<VirtualHost *:80>
    ServerName your-domain.com

    DocumentRoot /var/www/html/nextcloud

    <Directory /var/www/html/nextcloud/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
</VirtualHost>
EOF
a2enmod rewrite headers env dir mime
a2ensite nextcloud.conf



