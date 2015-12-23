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
    if prompt_yn "Do you wish to install quota?"; then
        INSTALL_APACHE2_SUEXEC=0
    else
        INSTALL_APACHE2_SUEXEC=1
    fi
else
    INSTALL_APACHE2_SUEXEC=1
fi

# ==================================================================
#  Basic virtual mailbox settings
# ==================================================================
if [ ! -d /var/vmail ]; then
    mkdir /var/vmail
	if [ $? -ne 0 ]; then
        echo "Error: Failed to create /var/vmail."
        exit 1
    fi
fi

if ! getent passwd vmail>/dev/null; then
    adduser --system --home /var/vmail --uid 5000 --group --disabled-login vmail
    if [ $? -ne 0 ]; then
        echo "Error: Failed to add user vmail."
        exit 1
    fi
fi

chown -R vmail:vmail /var/vmail
if [ $? -ne 0 ]; then
    echo "Error: Failed to set ownership for /var/vmail."
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
#  Restart the apache2 service
# ------------------------------------------------------------------
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
#  Postfix
# ==================================================================
echo "postfix postfix/mailname string $HOSTNAME" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections

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

if ! is_package_installed dovecot-mysql; then
    apt-get --yes install dovecot-mysql
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dovecot-mysql."
        exit 1
    fi
fi

# ==================================================================
#  Finish
# ==================================================================
echo ""
echo "Your server is now ready!"
echo ""