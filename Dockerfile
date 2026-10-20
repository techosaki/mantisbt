FROM php:8.5-apache

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		git \
		libfreetype6-dev \
		libicu-dev \
		libjpeg62-turbo-dev \
		libonig-dev \
		libpng-dev \
		libxml2-dev \
		libzip-dev \
		unzip \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
	&& docker-php-ext-install -j"$(nproc)" \
		gd \
		intl \
		mbstring \
		mysqli \
		soap \
		zip \
	&& a2enmod headers rewrite \
	&& sed -ri 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN printf 'upload_max_filesize=10M\npost_max_size=12M\n' \
	> /usr/local/etc/php/conf.d/mantisbt.ini \
	&& printf 'ServerName localhost\n' > /etc/apache2/conf-available/servername.conf \
	&& a2enconf servername

WORKDIR /var/www/html

# Install dependencies before copying the application to keep this layer cached
# while application source files are being edited.
COPY composer.json composer.lock ./
RUN composer install \
	--no-interaction \
	--no-progress \
	--prefer-dist

COPY . ./
COPY docker-entrypoint.sh /usr/local/bin/mantis-docker-entrypoint

RUN chmod +x /usr/local/bin/mantis-docker-entrypoint

EXPOSE 80

ENTRYPOINT ["mantis-docker-entrypoint"]
CMD ["apache2-foreground"]
