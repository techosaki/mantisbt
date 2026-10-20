#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOCAL_ROOT="/home/user/mantisbt"
readonly REMOTE_HOST="${DEPLOY_REMOTE_HOST:-dopack}"
readonly REMOTE_ROOT="${DEPLOY_REMOTE_ROOT:-/home/dopack/do-pack-system.com/public_html/bug-track}"
readonly REMOTE_PHP="${DEPLOY_REMOTE_PHP:-/home/dopack/bin/php}"
readonly REMOTE_COMPOSER="${DEPLOY_REMOTE_COMPOSER:-/usr/bin/composer}"

apply=false
delete=false
maintenance=true
run_composer=true
upgrade_database=true
maintenance_enabled=false

usage() {
	cat <<'USAGE'
Usage: ./dopack-tools/deploy-production.sh [options]

Without --apply, rsync runs in dry-run mode and does not change the server.

Options:
  --apply             Apply the deployment to the production server
  --delete            Delete remote files that no longer exist locally
                      (production-only files remain protected by exclusions)
  --no-maintenance    Do not enable the MantisBT maintenance page
  --skip-composer     Do not run Composer on the remote server
  --skip-db-upgrade   Do not run the MantisBT database schema upgrade
  -h, --help          Show this help

Environment overrides:
  DEPLOY_REMOTE_HOST      SSH host (default: dopack)
  DEPLOY_REMOTE_ROOT      Remote document root
  DEPLOY_REMOTE_PHP       Remote PHP CLI binary
  DEPLOY_REMOTE_COMPOSER  Remote Composer executable
USAGE
}

while (( $# > 0 )); do
	case "$1" in
		--apply)
			apply=true
			;;
		--delete)
			delete=true
			;;
		--no-maintenance)
			maintenance=false
			;;
		--skip-composer)
			run_composer=false
			;;
		--skip-db-upgrade)
			upgrade_database=false
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

if [[ ! -d "$LOCAL_ROOT/.git" ]]; then
	echo "Local project root is invalid: $LOCAL_ROOT" >&2
	exit 1
fi

for command_name in ssh rsync; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Required command is not installed: $command_name" >&2
		exit 1
	fi
done

echo "Checking production server..."
ssh "$REMOTE_HOST" bash -s -- \
	"$REMOTE_ROOT" "$REMOTE_PHP" "$REMOTE_COMPOSER" "$maintenance" "$run_composer" <<'REMOTE_CHECK'
set -eu

remote_root=$1
remote_php=$2
remote_composer=$3
use_maintenance=$4
use_composer=$5

test -d "$remote_root"
test -w "$remote_root"
test -x "$remote_php"
test -f "$remote_root/config/config_inc.php"
command -v rsync >/dev/null 2>&1

if [ "$use_composer" = true ]; then
	test -f "$remote_composer"
fi

if [ "$use_maintenance" = true ]; then
	test -f "$remote_root/mantis_offline.php.sample"
fi

"$remote_php" -r '
	if (version_compare(PHP_VERSION, "8.1.0", "<")) {
		fwrite(STDERR, "MantisBT requires PHP 8.1 or later." . PHP_EOL);
		exit(1);
	}
	foreach (["mysqli", "mbstring", "json"] as $extension) {
		if (!extension_loaded($extension)) {
			fwrite(STDERR, "Missing PHP extension: $extension" . PHP_EOL);
			exit(1);
		}
	}
'
REMOTE_CHECK

rsync_options=(
	--archive
	--compress
	--human-readable
	--itemize-changes
	--delay-updates
	--exclude=/.git/
	--exclude=/.github/
	--exclude=/.agents/
	--exclude=/.aws/
	--exclude=/.codex/
	--exclude=/.idea/
	--exclude=/.vscode/
	--exclude=/.dockerignore
	--exclude=/Dockerfile
	--exclude=/docker-compose.yml
	--exclude=/docker-entrypoint.sh
	--exclude=/node_modules/
	--exclude=/vendor/
	--exclude=/config/config_inc.php
	--exclude=/.htaccess
	--exclude=/.htpasswd
	--exclude=/.user.ini
	--exclude=/mantis_offline.php
)

if [[ "$delete" == true ]]; then
	rsync_options+=(--delete-delay)
fi

if [[ "$apply" != true ]]; then
	rsync_options+=(--dry-run)
	echo "Dry run only; no production files will be changed."
	echo "Comparing $LOCAL_ROOT/ with $REMOTE_HOST:$REMOTE_ROOT/"
	rsync "${rsync_options[@]}" "$LOCAL_ROOT/" "$REMOTE_HOST:$REMOTE_ROOT/"
	echo "Dry run completed. Run with --apply to deploy these changes."
	exit 0
fi

leave_maintenance_on_failure() {
	local exit_status=$?
	if (( exit_status != 0 )) && [[ "$maintenance_enabled" == true ]]; then
		echo "Deployment failed; MantisBT remains in maintenance mode." >&2
		echo "After resolving the problem, remove: $REMOTE_ROOT/mantis_offline.php" >&2
	fi
}
trap leave_maintenance_on_failure EXIT

if [[ "$maintenance" == true ]]; then
	echo "Enabling MantisBT maintenance mode..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" <<'REMOTE_MAINTENANCE_ON'
set -eu
remote_root=$1
if [ -e "$remote_root/mantis_offline.php" ]; then
	echo "Maintenance file already exists; refusing to overwrite it." >&2
	exit 1
fi
cp "$remote_root/mantis_offline.php.sample" "$remote_root/mantis_offline.php"
REMOTE_MAINTENANCE_ON
	maintenance_enabled=true
fi

echo "Synchronizing $LOCAL_ROOT/ to $REMOTE_HOST:$REMOTE_ROOT/"
rsync "${rsync_options[@]}" "$LOCAL_ROOT/" "$REMOTE_HOST:$REMOTE_ROOT/"

if [[ "$run_composer" == true ]]; then
	echo "Installing production Composer dependencies..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" "$REMOTE_PHP" "$REMOTE_COMPOSER" <<'REMOTE_COMPOSER_INSTALL'
set -eu
remote_root=$1
remote_php=$2
remote_composer=$3
"$remote_php" "$remote_composer" install \
	--working-dir="$remote_root" \
	--no-dev \
	--no-interaction \
	--no-progress \
	--prefer-dist \
	--optimize-autoloader
REMOTE_COMPOSER_INSTALL
fi

if [[ "$upgrade_database" == true ]]; then
	echo "Upgrading the MantisBT database schema..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" "$REMOTE_PHP" <<'REMOTE_DATABASE_UPGRADE'
set -eu
remote_root=$1
remote_php=$2
cd "$remote_root"
"$remote_php" admin/upgrade_unattended.php
REMOTE_DATABASE_UPGRADE
fi

if [[ "$maintenance_enabled" == true ]]; then
	echo "Disabling MantisBT maintenance mode..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" <<'REMOTE_MAINTENANCE_OFF'
set -eu
remote_root=$1
rm -f "$remote_root/mantis_offline.php"
REMOTE_MAINTENANCE_OFF
	maintenance_enabled=false
fi

echo "Production deployment completed successfully."
