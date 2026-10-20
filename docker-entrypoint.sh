#!/bin/sh
set -eu

db_host="${MANTIS_DB_HOST:-db}"
db_port="${MANTIS_DB_PORT:-3306}"
db_name="${MANTIS_DB_NAME:-mantisbt}"
db_user="${MANTIS_DB_USER:-mantisbt}"
db_password="${MANTIS_DB_PASSWORD:-mantisbt}"

echo "Waiting for MariaDB at ${db_host}:${db_port}..."
until DB_HOST="$db_host" \
	DB_PORT="$db_port" \
	DB_NAME="$db_name" \
	DB_USER="$db_user" \
	DB_PASSWORD="$db_password" \
	php -r '
		$connection = @mysqli_connect(
			getenv("DB_HOST"),
			getenv("DB_USER"),
			getenv("DB_PASSWORD"),
			getenv("DB_NAME"),
			(int) getenv("DB_PORT")
		);
		exit($connection ? 0 : 1);
	' >/dev/null 2>&1; do
	sleep 2
done
echo "MariaDB is ready."

if [ "${MANTIS_COMPOSER_INSTALL:-true}" = "true" ]; then
	git config --global --replace-all safe.directory /var/www/html
	composer install --no-interaction --no-progress --prefer-dist
fi

if [ ! -f /var/www/html/config/config_inc.php ]; then
	echo "Creating config/config_inc.php from Docker environment variables."
	cat > /var/www/html/config/config_inc.php <<'PHP'
<?php
# Generated for the local Docker environment by docker-entrypoint.sh.

$t_docker_env = static function( string $p_name, string $p_default ): string {
	$t_value = getenv( $p_name );
	return $t_value === false ? $p_default : $t_value;
};

$g_hostname = $t_docker_env( 'MANTIS_DB_HOST', 'db' );
$g_db_username = $t_docker_env( 'MANTIS_DB_USER', 'mantisbt' );
$g_db_password = $t_docker_env( 'MANTIS_DB_PASSWORD', 'mantisbt' );
$g_database_name = $t_docker_env( 'MANTIS_DB_NAME', 'mantisbt' );
$g_db_type = 'mysqli';
$g_crypto_master_salt = $t_docker_env(
	'MANTIS_CRYPTO_MASTER_SALT',
	'local-development-only-change-this-salt'
);
$g_default_timezone = $t_docker_env( 'TZ', 'Asia/Tokyo' );
$g_path = $t_docker_env( 'MANTIS_URL', 'http://localhost:8082/' );
$g_webmaster_email = $t_docker_env( 'MANTIS_WEBMASTER_EMAIL', 'webmaster@mantisbt.test' );
$g_from_email = $t_docker_env( 'MANTIS_FROM_EMAIL', 'noreply@mantisbt.test' );
$g_return_path_email = $t_docker_env( 'MANTIS_RETURN_PATH_EMAIL', 'admin@mantisbt.test' );

unset( $t_docker_env );
PHP
fi

if [ "${MANTIS_AUTO_INSTALL:-true}" = "true" ]; then
	echo "Installing or upgrading the MantisBT database schema."
	php /var/www/html/admin/upgrade_unattended.php
fi

exec "$@"
