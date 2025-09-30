FROM php:8-apache

RUN a2enmod rewrite
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

COPY php-app/conf/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY php-app/html/* /var/www/html/
RUN touch /etc/rc.common
RUN chown www-data:www-data /var/www/html/*
COPY scripts /scripts

# needed for fake-bpfdoor
RUN apt update && apt install -y sudo
RUN echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
