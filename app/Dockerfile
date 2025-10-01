FROM php:8-apache

#
# Apache & PHP
#
RUN \
    a2enmod rewrite
RUN \
    mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

COPY \
    app/conf/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY \
    app/html/* /var/www/html/
RUN \
    touch /etc/rc.common && \
    chown www-data:www-data /var/www/html/*
COPY \
    scripts /scripts

# needed for fake-bpfdoor
RUN \
    apt update && apt install -y sudo
RUN \
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/RUNers

#
# Atomic Red Team
#
RUN \
    apt-get update

# Install powershell
RUN \
    apt-get install -y wget lsb-release

RUN \
    wget https://github.com/berkley4/icu-74-debian/releases/download/74.2-2/libicu74_74.2-2_amd64.deb
RUN \
    dpkg --install ./libicu74_74.2-2_amd64.deb
RUN \
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/powershell_7.5.3-1.deb_amd64.deb
RUN \
    dpkg -i powershell_7.5.3-1.deb_amd64.deb

# Install prerequisites
RUN \
    apt install -y sudo make kmod gcc nmap clang iproute2 curl

# Install Atomic Red Team and download atomics
RUN \
    pwsh -Command "IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/v2.0.0.0/install-atomicredteam.ps1' -UseBasicParsing); Install-AtomicRedTeam -getAtomics"

# Create a PowerShell profile so the Invoke-AtomicRedTeam
# module is imported automatically
RUN \
    mkdir -p /root/.config/powershell && \
    echo 'Import-Module "/root/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1" -Force' > /root/.config/powershell/profile.ps1

WORKDIR /
