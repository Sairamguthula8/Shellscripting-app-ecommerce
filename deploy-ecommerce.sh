#!/bin/bash
set -e

#############################
# Variables
#############################
DB_NAME="ecomdb"
DB_USER="ecomuser"
DB_PASSWORD="ecompassword"

WEBROOT="/var/www/html"
REPO="https://github.com/Sairamguthula8/Shellscripting-app-ecommerce.git"

#############################
# Detect package manager
#############################
if command -v dnf &>/dev/null; then
    PKG="dnf"
else
    PKG="yum"
fi

echo "Using package manager: $PKG"

#############################
# Install Firewalld
#############################
$PKG install -y firewalld git

systemctl enable firewalld
systemctl start firewalld

#############################
# Install Database
#############################

if $PKG list available mariadb-server &>/dev/null; then
    DB_PACKAGE="mariadb-server"
    DB_SERVICE="mariadb"
elif $PKG list available mariadb105-server &>/dev/null; then
    DB_PACKAGE="mariadb105-server"
    DB_SERVICE="mariadb"
elif $PKG list available mysql-server &>/dev/null; then
    DB_PACKAGE="mysql-server"
    DB_SERVICE="mysqld"
else
    echo "No supported MariaDB/MySQL package found."
    exit 1
fi

echo "Installing $DB_PACKAGE"

$PKG install -y $DB_PACKAGE

systemctl enable $DB_SERVICE
systemctl start $DB_SERVICE

#############################
# Firewall
#############################

firewall-cmd --permanent --add-port=80/tcp || true
firewall-cmd --permanent --add-port=3306/tcp || true
firewall-cmd --reload || true

#############################
# Install Apache + PHP
#############################

if [ "$PKG" = "dnf" ]; then
    $PKG install -y httpd php php-mysqlnd git
else
    $PKG install -y httpd php php-mysqlnd git
fi

systemctl enable httpd
systemctl start httpd

#############################
# Configure Apache
#############################

sed -i 's/index.html/index.php/g' /etc/httpd/conf/httpd.conf

#############################
# Clone Application
#############################

rm -rf ${WEBROOT:?}/*

git clone $REPO $WEBROOT

#############################
# Create Database
#############################

mysql <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;

CREATE USER IF NOT EXISTS '$DB_USER'@'localhost'
IDENTIFIED BY '$DB_PASSWORD';

GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'localhost';

FLUSH PRIVILEGES;
EOF

#############################
# Load Data
#############################

cat >/tmp/db.sql <<EOF
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS products (
id mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
Name varchar(255),
Price varchar(255),
ImageUrl varchar(255),
PRIMARY KEY(id)
);

INSERT INTO products(Name,Price,ImageUrl)
VALUES
("Laptop","100","c-1.png"),
("Drone","200","c-2.png"),
("VR","300","c-3.png"),
("Tablet","50","c-5.png"),
("Watch","90","c-6.png"),
("Phone Covers","20","c-7.png"),
("Phone","80","c-8.png"),
("Laptop","150","c-4.png");
EOF

mysql < /tmp/db.sql

#############################
# Create .env
#############################

cat > $WEBROOT/.env <<EOF
DB_HOST=localhost
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
EOF

#############################
# Patch index.php
#############################

if ! grep -q "loadEnv" $WEBROOT/index.php; then

cat >/tmp/env.php <<'EOF'
<?php
function loadEnv($path){
    if(!file_exists($path)) return;

    foreach(file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line){
        if(strpos(trim($line),'#')===0) continue;

        list($k,$v)=explode("=",$line,2);

        putenv(trim($k)."=".trim($v));
    }
}

loadEnv(__DIR__."/.env");

$dbHost=getenv("DB_HOST");
$dbUser=getenv("DB_USER");
$dbPassword=getenv("DB_PASSWORD");
$dbName=getenv("DB_NAME");
?>
EOF

cat /tmp/env.php $WEBROOT/index.php > /tmp/index.php

mv /tmp/index.php $WEBROOT/index.php

fi

#############################
# Permissions
#############################

chown -R apache:apache $WEBROOT

chmod -R 755 $WEBROOT

systemctl restart httpd

#############################
# Done
#############################

echo
echo "======================================"
echo " Deployment Successful"
echo "======================================"
echo

IP=$(hostname -I | awk '{print $1}')

echo "Open:"
echo "http://$IP"

echo

curl http://localhost || true
