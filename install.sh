#!/bin/bash

# Check if a package is installed.
# Return 0 (true) is installed or 1 (false) if not installed
function is_package_installed() {
    if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
        return 1
    else
        return 0
    fi
}

function prompt_yn() {
    echo -n "$1 [y/n]: "

    while true; do
        read -n 1 -s value;
        if [[ $value == "y" ]] || [[ $value == "Y" ]];  then
            echo "y"
            return 0
        elif [[ $value == "n" ]] || [[ $value == "N" ]]; then
            echo "n"
            return 1
        fi
    done
}

function get_group_id()
{
    local __resultvar=$2
    local group_id=$(getent group $1 | cut -d: -f3);
    if [ $? -eq 0 ]; then
        if [ -z "$group_id" ]; then
            if [[ "$__resultvar" ]]; then
                eval $__resultvar=""
            else
                echo ""
            fi
        elif [ "$group_id" -eq "$group_id" ] 2>/dev/null; then
            if [[ "$__resultvar" ]]; then
                eval $__resultvar="'$group_id'"
            else
                echo "$group_id"
            fi
        else
            if [[ "$__resultvar" ]]; then
                eval $__resultvar=""
            else
                echo ""
            fi
        fi
    else
        if [[ "$__resultvar" ]]; then
            eval $__resultvar=""
        else
            echo ""
        fi

    fi
}

# ==================================================================
#  Main entry point
# ==================================================================
if [[ $(id -u) -ne 0 ]]; then 
    echo "Please run as root"
	exit 1
fi

# ------------------------------------------------------------------
#  Hostname
# ------------------------------------------------------------------
HOSTNAME=$(hostname -f);

# ------------------------------------------------------------------
#  Control Panel Database
# ------------------------------------------------------------------
MYSQL_CONTROLPANEL_DATABASE='psa'
MYSQL_CONTROLPANEL_USER_NAME='psa'
MYSQL_CONTROLPANEL_USER_PASSWORD='psa'

# ------------------------------------------------------------------
#  Virtual mail
# ------------------------------------------------------------------
VIRTUALMAIL_USER_NAME='vmail'
VIRTUALMAIL_GROUP_NAME=$VIRTUALMAIL_USER_NAME
VIRTUALMAIL_USER_ID=5000
VIRTUALMAIL_GROUP_ID=5000
VIRTUALMAIL_MBOXES_PATH='/var/vmail'

# ------------------------------------------------------------------
#  FTP
# ------------------------------------------------------------------
FTP_GROUP_NAME='ftpgroup'
FTP_GROUP_ID=2001
FTP_USER_NAME='ftpuser'
FTP_USER_ID=2001
#PROFTPD_SETTINGS
PROFTPD_SQL_MIN_GID=500

# ------------------------------------------------------------------
#  Non Privileged user
# ------------------------------------------------------------------
if prompt_yn "Do you wish to add a non-privileged user?"; then
    while true; do
        read -p "Username: " USER_NAME
        [[ -n "$USER_NAME" ]] && break;
        echo "Please try again"
    done

    while true; do
        while true; do
            read -s -p "Password: " USER_PASSWORD
            echo
            [[ -n "$USER_PASSWORD" ]] && break;
            echo "Please try again"
        done
        read -s -p "Password (again): " USER_PASSWORD_VERIFY
        echo 
        [ "$USER_PASSWORD" = "$USER_PASSWORD_VERIFY" ] && break
        echo "Please try again"
    done

    adduser --gecos ",,," --disabled-password $USER_NAME
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add user $USER_NAME."
        exit 1
    fi

    echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set the password for user $USER_NAME"
        exit 1
    fi
fi

# ------------------------------------------------------------------
#  MySQL
# ------------------------------------------------------------------
while true; do
    while true; do
        read -s -p "MySQL root password: " MYSQL_ROOT_PASSWORD
        echo
        [[ -n "$MYSQL_ROOT_PASSWORD" ]] && break;
        echo "Please try again"
    done
    read -s -p "MySQL root password (again): " MYSQL_ROOT_PASSWORD_VERIFY
    echo 
    [ "$MYSQL_ROOT_PASSWORD" = "$MYSQL_ROOT_PASSWORD_VERIFY" ] && break
    echo "Please try again"
done

# ------------------------------------------------------------------
#  Ask for packages
# ------------------------------------------------------------------
if ! is_package_installed fail2ban; then
    if prompt_yn "Do you wish to install fail2ban?"; then
        INSTALL_FAIL2BAN=0
    else
        INSTALL_FAIL2BAN=1
    fi
else
    INSTALL_FAIL2BAN=1
fi

if ! is_package_installed quota; then
    if prompt_yn "Do you wish to install quota?"; then
        INSTALL_QUOTA=0
    else
        INSTALL_QUOTA=1
    fi
else
    INSTALL_QUOTA=1
fi

if ! is_package_installed awstats; then
    if prompt_yn "Do you wish to install awstats?"; then
        INSTALL_AWSTATS=0
    else
        INSTALL_AWSTATS=1
    fi
else
    INSTALL_AWSTATS=1
fi

if ! is_package_installed mod-pagespeed-stable; then
    if prompt_yn "Do you wish to install pagespeed module?"; then
        INSTALL_PAGESPEED=0
    else
        INSTALL_PAGESPEED=1
    fi
else
    INSTALL_PAGESPEED=1
fi

if ! is_package_installed apache2-suexec; then
    if prompt_yn "Do you wish to install apache2 suexec?"; then
        INSTALL_APACHE2_SUEXEC=0
    else
        INSTALL_APACHE2_SUEXEC=1
    fi
else
    INSTALL_APACHE2_SUEXEC=1
fi

if ! is_package_installed phpmyadmin; then
    if prompt_yn "Do you wish to install phpmyadmin?"; then
        INSTALL_PHPMYADMIN=0
    else
        INSTALL_PHPMYADMIN=1
    fi
else
    INSTALL_PHPMYADMIN=1
fi

if ! is_package_installed proftpd-basic; then
    if prompt_yn "Do you wish to install proFTPd?"; then
        INSTALL_PROFTPD=0
    else
        INSTALL_PROFTPD=1
    fi
elif ! is_package_installed proftpd-mod-mysql; then
    if prompt_yn "Do you wish to install proFTPd?"; then
        INSTALL_PROFTPD=0
    else
        INSTALL_PROFTPD=1
    fi
else
    INSTALL_PROFTPD=1
fi



# ==================================================================
#  Basic virtual mailbox settings
# ==================================================================
if [ ! -d $VIRTUALMAIL_MBOXES_PATH ]; then
    mkdir -p $VIRTUALMAIL_MBOXES_PATH
	if [ $? -ne 0 ]; then
        echo "Error: Failed to create $VIRTUALMAIL_MBOXES_PATH."
        exit 1
    fi
fi

if ! getent passwd $VIRTUALMAIL_USER_NAME>/dev/null; then
    adduser --system --home $VIRTUALMAIL_MBOXES_PATH --uid $VIRTUALMAIL_USER_ID --group --disabled-login $VIRTUALMAIL_USER_NAME
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add user vmail."
        exit 1
    fi
	VIRTUALMAIL_GROUP_NAME=$VIRTUALMAIL_USER_NAME
fi

chown -R $VIRTUALMAIL_USER_NAME:$VIRTUALMAIL_GROUP_NAME $VIRTUALMAIL_MBOXES_PATH
if [ $? -ne 0 ]; then
    echo "Error: Failed to set ownership for $VIRTUALMAIL_MBOXES_PATH."
    exit 1
fi

# ==================================================================
#  Prepare APT
# ==================================================================
if ! is_package_installed wget; then
    apt-get --yes update
    apt-get --yes upgrade
    apt-get --yes install wget
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install wget."
        exit 1
    fi
fi

if [ ! -f /etc/apt/sources.list.d/dotdeb.list ]; then
    echo "deb http://packages.dotdeb.org wheezy all" > /etc/apt/sources.list.d/dotdeb.list
    echo "deb http://packages.dotdeb.org wheezy-php56-zts all" >> /etc/apt/sources.list

    wget --no-check-certificate https://www.dotdeb.org/dotdeb.gpg
    apt-key add dotdeb.gpg
    rm dotdeb.gpg
fi

export DEBIAN_FRONTEND noninteractive

apt-get --yes update
apt-get --yes upgrade
apt-get --yes dist-upgrade

# ==================================================================
#  Sudo
# ==================================================================
if ! is_package_installed sudo; then
    apt-get --yes install sudo
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install sudo."
        exit 1
    fi
fi

if [ -n "$USER_NAME" ]; then
    usermod -aG sudo $USER_NAME
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add $USER_NAME to the sudo group."
        exit 1
    fi

	if [ -f /etc/ssh/sshd_config ]; then
        sed -i "s/#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
        sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config

        service ssh restart
    fi
fi

# ==================================================================
#  Fail2ban
# ==================================================================
if [ $INSTALL_FAIL2BAN -eq 0 ]; then
    apt-get --yes install fail2ban
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install fail2ban."
        exit 1
    fi
fi

# ==================================================================
#  Open SSL
# ==================================================================
if ! is_package_installed openssl; then
    apt-get --yes install openssl
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install openssl."
        exit 1
    fi
fi

if ! is_package_installed ssl-cert; then
    apt-get --yes install ssl-cert
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install ssl-cert."
        exit 1
    fi
fi

# ==================================================================
#  Quota
# ==================================================================
if [ $INSTALL_QUOTA -eq 0 ]; then
    apt-get --yes install quota
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install quota."
        exit 1
    fi
fi

# ==================================================================
#  MySQL
# ==================================================================
if ! is_package_installed mysql-server; then
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections

    apt-get --yes install mysql-server
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install mysql-server."
        exit 1
    fi
else
    # Reset the password for root
    service mysql stop
    sleep 3

    killall -9 mysqld_safe mysqld
    sleep 3

    mysqld_safe --skip-grant-tables &
    sleep 5

    mysql -uroot -e "UPDATE mysql.user SET password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root'; FLUSH PRIVILEGES;"

    killall -9 mysqld_safe mysqld
    sleep 3

    service mysql start
fi

# User creation is separated as there is no IF EXISTS prior to mySQL 5.7.6! Therefore this may fail if the user exist
mysql -uroot -p$MYSQL_ROOT_PASSWORD <<EOF
    CREATE USER $MYSQL_CONTROLPANEL_USER_NAME@localhost IDENTIFIED BY '$MYSQL_CONTROLPANEL_USER_PASSWORD';

    GRANT USAGE ON *.* TO $MYSQL_CONTROLPANEL_USER_NAME@localhost;

    FLUSH PRIVILEGES;
EOF

mysql -uroot -p$MYSQL_ROOT_PASSWORD <<EOF
    DROP DATABASE IF EXISTS $MYSQL_CONTROLPANEL_DATABASE;

    CREATE DATABASE IF NOT EXISTS $MYSQL_CONTROLPANEL_DATABASE
        DEFAULT CHARACTER SET=utf8
        DEFAULT COLLATE=utf8_general_ci;

    USE $MYSQL_CONTROLPANEL_DATABASE;

    CREATE TABLE IF NOT EXISTS domains (
        id int(10) unsigned NOT NULL auto_increment,
        name varchar(255) NOT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY name (name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 DEFAULT COLLATE=utf8_general_ci;

    CREATE TABLE IF NOT EXISTS mail (
        id int(10) unsigned NOT NULL auto_increment,
        mail_name varchar(245)  character set ascii NOT NULL,
        domain_id int(10) unsigned NOT NULL,
        password varchar(255) NULL,
        PRIMARY KEY(id),
        UNIQUE KEY domain_id (domain_id, mail_name),
        FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 DEFAULT COLLATE=utf8_general_ci;

    CREATE TABLE IF NOT EXISTS mail_aliases (
        id int(10) unsigned NOT NULL auto_increment,
        mail_id int(10) unsigned NOT NULL,
        alias varchar(255) NULL,
        PRIMARY KEY(id),
        UNIQUE KEY mail_id (mail_id, alias),
        FOREIGN KEY (mail_id) REFERENCES mail(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 DEFAULT COLLATE=utf8_general_ci;

    CREATE TABLE IF NOT EXISTS sys_groups (
        groupname varchar(16) NOT NULL,
        gid smallint(6) NOT NULL DEFAULT '$FTP_GROUP_ID',
        members varchar(16),
        KEY groupname (groupname)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

    CREATE TABLE IF NOT EXISTS sys_users (
        id int(10) unsigned NOT NULL AUTO_INCREMENT,
        userid varchar(32) COLLATE utf8_general_ci NOT NULL DEFAULT '',
        passwd varchar(32) COLLATE utf8_general_ci NOT NULL DEFAULT '',
        uid smallint(6) NOT NULL DEFAULT '$FTP_USER_ID',
        gid smallint(6) NOT NULL DEFAULT '$FTP_GROUP_ID',
        homedir varchar(255) COLLATE utf8_general_ci NOT NULL DEFAULT '',
        shell varchar(16) COLLATE utf8_general_ci NOT NULL DEFAULT '/sbin/nologin',
        PRIMARY KEY (id),
        UNIQUE KEY userid (userid)
    ) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

    INSERT INTO domains (name) VALUES ('$HOSTNAME');
	
	GRANT ALL PRIVILEGES ON $MYSQL_CONTROLPANEL_DATABASE.* TO $MYSQL_CONTROLPANEL_USER_NAME@localhost;

    FLUSH PRIVILEGES;
EOF

if [ -n "$USER_NAME" ]; then
    USER_GID=$(id -u $USER_NAME)
    if [ $? -eq 0 ]; then
        mysql -uroot -p$MYSQL_ROOT_PASSWORD $MYSQL_CONTROLPANEL_DATABASE -e "INSERT INTO sys_groups (gid, groupname, members) VALUES ('$USER_GID', '$USER_NAME', '');"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add $USER_NAME to sys_groups table."
            exit 1
        fi

        USER_ID=$(id -u $USER_NAME)
        if [ $? -eq 0 ]; then
            SYS_USERS_PASSWORD=$(echo "{md5}"`/bin/echo -n "$USER_PASSWORD" | openssl dgst -binary -md5 | openssl enc -base64`)
            mysql -uroot -p$MYSQL_ROOT_PASSWORD $MYSQL_CONTROLPANEL_DATABASE -e "INSERT INTO sys_users (userid, passwd, uid, gid, homedir, shell) VALUES ('$USER_NAME', '$SYS_USERS_PASSWORD', '$USER_ID', '$USER_GID', '/home/$USER_NAME', '/bin/bash');"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to add $USER_NAME to sys_users table."
                exit 1
            fi
        fi
    fi
fi

# ==================================================================
#  PHP
# ==================================================================
if ! is_package_installed php5; then
    apt-get --yes install php5
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5."
        exit 1
    fi
fi

# ------------------------------------------------------------------
#  PHP modules
# ------------------------------------------------------------------
if ! is_package_installed php-pear; then
    apt-get --yes install php-pear
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php-pear."
        exit 1
    fi
fi

if ! is_package_installed php5-cgi; then
    apt-get --yes install php5-cgi
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-cgi."
        exit 1
    fi
fi

if ! is_package_installed php5-cli; then
    apt-get --yes install php5-cli
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-cli."
        exit 1
    fi
fi

if ! is_package_installed php5-curl; then
    apt-get --yes install php5-curl
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-curl."
        exit 1
    fi
fi

if ! is_package_installed php5-gd; then
    apt-get --yes install php5-gd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-gd."
        exit 1
    fi
fi

if ! is_package_installed php5-imap; then
    apt-get --yes install php5-imap
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-imap."
        exit 1
    fi
fi

if ! is_package_installed php5-intl; then
    apt-get --yes install php5-intl
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-intl."
        exit 1
    fi
fi

if ! is_package_installed php5-mcrypt; then
    apt-get --yes install php5-mcrypt
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-mcrypt."
        exit 1
    fi
fi

if ! is_package_installed php5-mysql; then
    apt-get --yes install php5-mysql
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-mysql."
        exit 1
    fi
fi

if ! is_package_installed php5-recode; then
    apt-get --yes install php5-recode
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install php5-recode."
        exit 1
    fi
fi

# ==================================================================
#  Apache
# ==================================================================
if ! is_package_installed apache2; then
    apt-get --yes install apache2
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install apache2."
        exit 1
    fi
fi

if ! is_package_installed apache2-utils; then
    apt-get --yes install apache2-utils
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install apache2-utils."
        exit 1
    fi
fi

if ! is_package_installed apache2-mpm-prefork; then
    apt-get --yes install apache2-mpm-prefork
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install apache2-mpm-prefork."
        exit 1
    fi
fi

if ! is_package_installed libapache2-mod-php5; then
    apt-get --yes install libapache2-mod-php5
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install libapache2-mod-php5."
        exit 1
    fi
fi

if [ $INSTALL_PAGESPEED -eq 0 ]; then
    if ! is_package_installed mod-pagespeed-stable; then
        ARCH=`dpkg --print-architecture`;

        wget --no-check-certificate "https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_${ARCH}.deb"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download mod-pagespeed-stable."
            exit 1
        fi

        dpkg -i mod-pagespeed-stable_current_${ARCH}.deb
		if [ $? -ne 0 ]; then
            echo "Error: Failed to install mod-pagespeed-stable."
            exit 1
        fi

        apt-get -f install
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install mod-pagespeed-stable."
            exit 1
        fi
    fi
fi

if [ $INSTALL_APACHE2_SUEXEC -eq 0 ]; then
    if ! is_package_installed apache2-suexec; then
        apt-get --yes install apache2-suexec
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install apache2-suexec."
            exit 1
        fi
    fi
fi

# ------------------------------------------------------------------
#  Enable apache2 modules
# ------------------------------------------------------------------
a2enmod rewrite
a2enmod deflate
a2enmod ssl

if ! is_package_installed mod-pagespeed-stable; then
    a2enmod pagespeed
fi

# ------------------------------------------------------------------
#  Virtual hosting
# ------------------------------------------------------------------
GROUP_WWW_DATA_GID=$(get_group_id www-data)
if [ -n "$GROUP_WWW_DATA_GID" ]; then
    mysql -u$MYSQL_CONTROLPANEL_USER_NAME -p$MYSQL_CONTROLPANEL_USER_PASSWORD $MYSQL_CONTROLPANEL_DATABASE -e "INSERT INTO sys_groups (groupname, gid, members) VALUES ('www-data', $GROUP_WWW_DATA_GID, '');"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add group www-data to database."
        exit 1
    fi

    chgrp -R www-data /var/www
    chmod 775 -R /var/www
    chmod g+s /var/www

    if [ $GROUP_WWW_DATA_GID -lt $PROFTPD_SQL_MIN_GID ]; then
        PROFTPD_SQL_MIN_GID=$GROUP_WWW_DATA_GID
    fi
fi

if [ ! -d /var/www/$HOSTNAME ]; then
    mkdir -p /var/www/$HOSTNAME/htdocs
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create /var/www/$HOSTNAME/htdocs."
        exit 1
    fi

    mkdir /var/www/$HOSTNAME/cgi-bin

    if [ -f /var/www/index.html ]; then
        cp /var/www/index.html /var/www/$HOSTNAME/htdocs/index.html
    fi

    if [ ! -f /etc/apache2/sites-available/$HOSTNAME ]; then
        if [ -f /etc/apache2/sites-available/default ]; then
            a2dissite default

            cp /etc/apache2/sites-available/default /etc/apache2/sites-available/$HOSTNAME
            sed -i "s%/var/www%/var/www/${HOSTNAME}/htdocs%" /etc/apache2/sites-available/$HOSTNAME

            if [ -f /etc/apache2/sites-available/$HOSTNAME ]; then
                rm /etc/apache2/sites-available/default
                a2ensite $HOSTNAME
            fi
        fi
    fi

    if [ ! -f /etc/apache2/sites-available/$HOSTNAME-ssl ]; then
        if [ -f /etc/apache2/sites-available/default-ssl ]; then
            # Instead of creating the directory we set a symbolic link
            if [ ! -d /var/www/$HOSTNAME/htsdocs ]; then
                ln -s /var/www/$HOSTNAME/htdocs/ /var/www/$HOSTNAME/htsdocs
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to create /var/www/$HOSTNAME/htsdocs."
                    exit 1
                fi
            fi

            a2dissite default-ssl

		    cp /etc/apache2/sites-available/default-ssl /etc/apache2/sites-available/$HOSTNAME-ssl
            sed -i "s%/var/www%/var/www/${HOSTNAME}/htsdocs%" /etc/apache2/sites-available/$HOSTNAME-ssl
            #SSLCertificateFile    /etc/ssl/certs/ssl-cert-snakeoil.pem
            #SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

            if [ -f /etc/apache2/sites-available/$HOSTNAME-ssl ]; then
                rm /etc/apache2/sites-available/default-ssl
                a2ensite $HOSTNAME-ssl
            fi
        fi
    fi

    if [ -f /var/www/index.html ]; then
        if [ -f /var/www/$HOSTNAME/htdocs/index.html ]; then
            rm /var/www/index.html
        fi
    fi
fi

if [ ! -f /etc/apache2/sites-available/$HOSTNAME ]; then
    echo "Error: Failed to create the virtual host file for $HOSTNAME."
    exit 1
fi

# ------------------------------------------------------------------
#  Create the control panel vhost
# ------------------------------------------------------------------
if [ ! -d /usr/share/phpanel/public ]; then
    mkdir -p /usr/share/phpanel/public
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create /usr/share/phpanel."
        exit 1
    fi

    chmod -R +755 /usr/share/phpanel
fi

if [ ! -f /etc/apache2/conf.d/phpanel.conf ]; then
    cp resources/phpanel/apache.conf /etc/apache2/conf.d/phpanel.conf
fi

# ==================================================================
#  PHPMyAdmin
# ==================================================================
if [ $INSTALL_PHPMYADMIN -eq 0 ]; then
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/password-confirm password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/setup-password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/setup-username string root" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/db/app-user string root" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

    apt-get --yes install phpmyadmin
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install phpmyadmin."
        exit 1
    fi
fi

if [ ! -f /etc/phpmyadmin/apache.conf ]; then
    if [ -f /etc/apache2/conf.d/phpmyadmin.conf ]; then
        cp /etc/apache2/conf.d/phpmyadmin.conf /etc/phpmyadmin/apache.conf
    fi
fi
if [ -f /etc/apache2/conf.d/phpmyadmin.conf ]; then
    rm /etc/apache2/conf.d/phpmyadmin.conf
fi

# ==================================================================
#  Restart the apache2 service
# ==================================================================
service apache2 restart

# ==================================================================
#  AWStats
# ==================================================================
if [ $INSTALL_AWSTATS -eq 0 ]; then
    apt-get --yes install awstats
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install awstats."
        exit 1
    fi
fi

# ==================================================================
#  ProFTPd
# ==================================================================
if [ $INSTALL_PROFTPD -eq 0 ]; then
    if ! is_package_installed proftpd-basic; then
        echo "proftpd-basic shared/proftpd/inetd_or_standalone select standalone" | debconf-set-selections

        apt-get --yes install proftpd-basic
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install proftpd-basic."
            exit 1
        fi
    fi

    if ! is_package_installed proftpd-mod-mysql; then
        apt-get --yes install proftpd-mod-mysql
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install proftpd-mod-mysql."
            exit 1
        fi
    fi

	# --------------------------------------------------------------
    #  Backup the files we are going to change
    # --------------------------------------------------------------
    if [ ! -f /etc/proftpd/proftpd.conf.backup ]; then
        cp /etc/proftpd/proftpd.conf /etc/proftpd/proftpd.conf.backup
        if [ $? -ne 0 ]; then
            echo "Error: Failed to backup the coniguration file of proftpd."
            exit 1
        fi
    fi

    if ! getent group $FTP_GROUP_NAME>/dev/null; then
        addgroup --system --gid $FTP_GROUP_ID $FTP_GROUP_NAME
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add group $FTP_GROUP_NAME."
            exit 1
        fi
    fi

    if ! getent passwd $FTP_USER_NAME>/dev/null; then
        adduser --system --home /var/www --uid $FTP_USER_ID --ingroup $FTP_GROUP_NAME --disabled-login $FTP_USER_NAME
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add user $FTP_USER_NAME."
            exit 1
        fi
    fi

    sed -i 's|# RequireValidShell|RequireValidShell|g' /etc/proftpd/proftpd.conf
    sed -i 's|# DefaultRoot|DefaultRoot|g' /etc/proftpd/proftpd.conf
	sed -i 's|#Include /etc/proftpd/sql.conf|Include /etc/proftpd/sql.conf|g' /etc/proftpd/proftpd.conf

    cat << EOF > /etc/proftpd/sql.conf
#
# Proftpd sample configuration for SQL-based authentication.
#
# (This is not to be used if you prefer a PAM-based SQL authentication)
#

<IfModule mod_sql.c>
#
# Choose a SQL backend among MySQL or PostgreSQL.
# Both modules are loaded in default configuration, so you have to specify the backend
# or comment out the unused module in /etc/proftpd/modules.conf.
# Use 'mysql' or 'postgres' as possible values.
#
SQLBackend     mysql

#SQLEngine on
#SQLAuthenticate on
SQLAuthenticate users groups
#
# Use both a crypted or plaintext password
SQLAuthTypes OpenSSL Crypt

#
# Connection
SQLConnectInfo $MYSQL_CONTROLPANEL_DATABASE@localhost $MYSQL_CONTROLPANEL_USER_NAME $MYSQL_CONTROLPANEL_USER_PASSWORD

# Describes both users/groups tables
#
SQLUserInfo sys_users userid passwd uid gid homedir shell
SQLGroupInfo sys_groups groupname gid members

# set min UID and GID - otherwise these are 999 each
SQLMinUserGID   $PROFTPD_SQL_MIN_GID

RootLogin off
RequireValidShell off

</IfModule>
EOF

    sed -i 's|#LoadModule mod_sql.c|LoadModule mod_sql.c|g' /etc/proftpd/modules.conf
    sed -i 's|#LoadModule mod_sql_mysql.c|LoadModule mod_sql_mysql.c|g' /etc/proftpd/modules.conf

    mysql -uroot -p$MYSQL_ROOT_PASSWORD $MYSQL_CONTROLPANEL_DATABASE -e "INSERT INTO sys_groups (groupname, gid, members) VALUES ('$FTP_GROUP_NAME', '$FTP_GROUP_ID', '');"

	service proftpd restart
fi

# ==================================================================
#  Dovecot
# ==================================================================
echo "dovecot-core dovecot-core/create-ssl-cert boolean true" | debconf-set-selections
echo "dovecot-core dovecot-core/ssl-cert-name string $HOSTNAME" | debconf-set-selections

if ! is_package_installed dovecot-core; then
    apt-get --yes install dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot."
        exit 1
    fi
fi

if ! is_package_installed dovecot-imapd; then
    apt-get --yes install dovecot-imapd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-imapd."
        exit 1
    fi
fi

if ! is_package_installed dovecot-pop3d; then
    apt-get --yes install dovecot-pop3d
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-pop3d."
        exit 1
    fi
fi

if ! is_package_installed dovecot-lmtpd; then
    apt-get --yes install dovecot-lmtpd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-lmtpd."
        exit 1
    fi
fi

if ! is_package_installed dovecot-sieve; then
    apt-get --yes install dovecot-sieve
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-sieve."
        exit 1
    fi
fi

if ! is_package_installed dovecot-mysql; then
    apt-get --yes install dovecot-mysql
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-mysql."
        exit 1
    fi
fi

# ------------------------------------------------------------------
#  Configure Dovecot
# ------------------------------------------------------------------
sed -i "s|^mail_location.*|mail_location = maildir:$VIRTUALMAIL_MBOXES_PATH/%d/%n|" /etc/dovecot/conf.d/10-mail.conf

sed -i "s/^auth_mechanisms = plain.*$/auth_mechanisms = plain login/" /etc/dovecot/conf.d/10-auth.conf
sed -i "s/^\!include auth-system.conf.ext/\#\!include auth-system.conf.ext/" /etc/dovecot/conf.d/10-auth.conf
sed -i "s/^\#\!include auth-sql.conf.ext/\!include auth-sql.conf.ext/" /etc/dovecot/conf.d/10-auth.conf

cat <<EOF > /etc/dovecot/conf.d/auth-sql.conf.ext
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=$VIRTUALMAIL_USER_NAME gid=$VIRTUALMAIL_GROUP_NAME home=$VIRTUALMAIL_MBOXES_PATH/%d/%n
}
EOF

cp resources/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy resources/dovecot/dovecot-sql.conf.ext to /etc/dovecot/dovecot-sql.conf.ext."
    exit 1
fi
sed -i "s/^driver =.*$/driver = mysql/" /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/^connect =.*$/connect = host=127.0.0.1 dbname=$MYSQL_CONTROLPANEL_DATABASE user=$MYSQL_CONTROLPANEL_USER_NAME password=$MYSQL_CONTROLPANEL_USER_PASSWORD/" /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/^default_pass_scheme =.*$/default_pass_scheme = SHA512-CRYPT/" /etc/dovecot/dovecot-sql.conf.ext
sed -i "s/^password_query =.*$/password_query = SELECT m.mail_name AS username, d.name AS domain, m.password AS password FROM mail m INNER JOIN domains d ON m.domain_id = d.id WHERE m.mail_name='%n' AND d.name='%d'/" /etc/dovecot/dovecot-sql.conf.ext

cp resources/dovecot/10-master.conf /etc/dovecot/conf.d/10-master.conf
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy resources/dovecot/10-master.conf to /etc/dovecot/conf.d/10-master.conf."
    exit 1
fi
sed -i "s/^\s*user = vmail\s*$/user = $VIRTUALMAIL_USER_NAME/" /etc/dovecot/conf.d/10-master.conf

sed -i "/^ssl =.*$/d" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s/^#ssl =.*$/#ssl = yes\nssl = required/" /etc/dovecot/conf.d/10-ssl.conf

#chown -R $VIRTUALMAIL_USER_NAME:dovecot /etc/dovecot
#chmod -R o-rwx /etc/dovecot

service dovecot restart

# ------------------------------------------------------------------
#  Restart dovecot
# ------------------------------------------------------------------
service dovecot restart

# ==================================================================
#  Postfix
# ==================================================================
echo "postfix postfix/mailname string $HOSTNAME" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections

if [ -f /etc/init.d/sendmail ]; then
    service sendmail stop
fi

if ! is_package_installed postfix; then
    apt-get --yes install postfix postfix-mysql
	if [ $? -ne 0 ]; then
        echo "Error: Failed to install postfix."
        exit 1
    fi
fi

if ! is_package_installed postfix-mysql; then
    apt-get --yes install postfix-mysql
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install postfix-mysql."
        exit 1
    fi
fi

cat <<EOF > /etc/postfix/mysql-virtual-mailbox-domains.cf
user = $MYSQL_CONTROLPANEL_USER_NAME
password = $MYSQL_CONTROLPANEL_USER_PASSWORD
hosts = 127.0.0.1
dbname = $MYSQL_CONTROLPANEL_DATABASE
query = SELECT name AS virtual FROM domains WHERE name='%s'
EOF

cat <<EOF > /etc/postfix/mysql-virtual-mailbox-maps.cf
user = $MYSQL_CONTROLPANEL_USER_NAME
password = $MYSQL_CONTROLPANEL_USER_PASSWORD
hosts = 127.0.0.1
dbname = $MYSQL_CONTROLPANEL_DATABASE
query = SELECT CONCAT(m.mail_name, '@', d.name) AS email FROM mail m INNER JOIN domains d ON m.domain_id = d.id WHERE m.mail_name='%u' AND d.name='%d'
EOF

cat <<EOF > /etc/postfix/mysql-virtual-alias-maps.cf
user = $MYSQL_CONTROLPANEL_USER_NAME
password = $MYSQL_CONTROLPANEL_USER_PASSWORD
hosts = 127.0.0.1
dbname = $MYSQL_CONTROLPANEL_DATABASE
query =  SELECT CONCAT(m.mail_name, '@', d.name) AS destination FROM mail_aliases a INNER JOIN mail m ON a.mail_id = m.id INNER JOIN domains d ON m.domain_id = d.id WHERE a.alias='%u' AND d.name='%d'
EOF

# ------------------------------------------------------------------
#  File permission
# ------------------------------------------------------------------
#chmod o= /etc/postfix/mysql-*
#chgrp postfix /etc/postfix/mysql-*

# ------------------------------------------------------------------
#  Postfix configuration
# ------------------------------------------------------------------
postconf -e "mydestination = localhost"
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf"
postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination" 

postconf -e "smtpd_tls_cert_file=/etc/dovecot/dovecot.pem"
postconf -e "smtpd_tls_key_file=/etc/dovecot/private/dovecot.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only = yes"

postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"

postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"

sed -i "s/#submission inet n       -       -       -       -       smtpd/submission inet n       -       -       -       -       smtpd/" /etc/postfix/master.cf
sed -i "s/#  -o syslog_name=postfix\/submission/  -o syslog_name=postfix\/submission/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_tls_security_level=encrypt/  -o smtpd_tls_security_level=encrypt/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_sasl_auth_enable=yes/  -o smtpd_sasl_auth_enable=yes/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_client_restrictions=permit_sasl_authenticated,reject/  -o smtpd_client_restrictions=permit_sasl_authenticated,reject/" /etc/postfix/master.cf
sed -i "s/#smtps     inet  n       -       -       -       -       smtpd/smtps     inet  n       -       -       -       -       smtpd/" /etc/postfix/master.cf
sed -i "s/#  -o syslog_name=postfix\/smtps/  -o syslog_name=postfix\/smtps/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_tls_wrappermode=yes/  -o smtpd_tls_wrappermode=yes/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_sasl_auth_enable=yes/  -o smtpd_sasl_auth_enable=yes/" /etc/postfix/master.cf
sed -i "s/#  -o smtpd_client_restrictions=permit_sasl_authenticated,reject/  -o smtpd_client_restrictions=permit_sasl_authenticated,reject/" /etc/postfix/master.cf

# ------------------------------------------------------------------
#  Restart postfix and dovecot
# ------------------------------------------------------------------
service postfix restart
service dovecot restart

# ==================================================================
#  Finish
# ==================================================================
echo ""
echo "Your server is now ready!"
echo ""