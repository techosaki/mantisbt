#!/usr/bin/env bash
set -Eeuo pipefail

readonly LOCAL_ROOT="/home/user/mantisbt"
readonly REMOTE_HOST="${DEPLOY_REMOTE_HOST:-dopack}"
readonly REMOTE_ROOT="${DEPLOY_REMOTE_ROOT:-/home/dopack/do-pack-system.com/public_html/bug-track}"
readonly REMOTE_PHP="${DEPLOY_REMOTE_PHP:-/home/dopack/bin/php}"
readonly REMOTE_COMPOSER_PHP="${DEPLOY_REMOTE_COMPOSER_PHP:-/opt/php-8.3.35/bin/php}"
readonly REMOTE_COMPOSER="${DEPLOY_REMOTE_COMPOSER:-/usr/bin/composer}"

apply=false
delete=true
maintenance=true
run_composer=true
upgrade_database=true
maintenance_enabled=false

usage() {
	cat <<'USAGE'
使用方法: ./dopack-tools/deploy-production.sh [オプション]

--applyを指定しない場合はドライランとなり、本番サーバーを変更しません。

オプション:
  --apply             本番サーバーへデプロイを適用する
  --delete            削除同期を有効にする（既定の動作）
  --no-delete         リモートにのみ存在するファイルを削除しない
                      （本番固有ファイルは常に除外設定で保護されます）
  --no-maintenance    MantisBTをメンテナンスモードに切り替えない
  --skip-composer     リモートサーバーでComposerを実行しない
  --skip-db-upgrade   MantisBTのデータベーススキーマを更新しない
  -h, --help          このヘルプを表示する

環境変数による設定変更:
  DEPLOY_REMOTE_HOST      SSH接続先（既定値: dopack）
  DEPLOY_REMOTE_ROOT      リモートの公開ルート
  DEPLOY_REMOTE_PHP       リモートのPHP CLI実行ファイル
  DEPLOY_REMOTE_COMPOSER_PHP
                          Composer実行用のPHP CLI実行ファイル
  DEPLOY_REMOTE_COMPOSER  リモートのComposer実行ファイル
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
		--no-delete)
			delete=false
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
			echo "不明なオプションです: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

if [[ ! -d "$LOCAL_ROOT/.git" ]]; then
	echo "ローカルのプロジェクトルートが正しくありません: $LOCAL_ROOT" >&2
	exit 1
fi

for command_name in ssh rsync; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "必要なコマンドがインストールされていません: $command_name" >&2
		exit 1
	fi
done

echo "本番サーバーの環境を確認しています..."
ssh "$REMOTE_HOST" bash -s -- \
	"$REMOTE_ROOT" "$REMOTE_PHP" "$REMOTE_COMPOSER_PHP" "$REMOTE_COMPOSER" \
	"$maintenance" "$run_composer" <<'REMOTE_CHECK'
set -eu

remote_root=$1
remote_php=$2
remote_composer_php=$3
remote_composer=$4
use_maintenance=$5
use_composer=$6

test -d "$remote_root"
test -w "$remote_root"
test -x "$remote_php"
test -f "$remote_root/config/config_inc.php"
command -v rsync >/dev/null 2>&1

if [ "$use_composer" = true ]; then
	test -x "$remote_composer_php"
	test -f "$remote_composer"
fi

if [ "$use_maintenance" = true ]; then
	test -f "$remote_root/mantis_offline.php.sample"
fi

"$remote_php" -r '
	if (version_compare(PHP_VERSION, "8.1.0", "<")) {
		fwrite(STDERR, "MantisBTの実行にはPHP 8.1以上が必要です。" . PHP_EOL);
		exit(1);
	}
	foreach (["mysqli", "mbstring", "json"] as $extension) {
		if (!extension_loaded($extension)) {
			fwrite(STDERR, "必要なPHP拡張がありません: $extension" . PHP_EOL);
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
	echo "ドライランを実行します。本番ファイルは変更されません。"
	echo "$LOCAL_ROOT/ と $REMOTE_HOST:$REMOTE_ROOT/ の差分を確認しています。"
	rsync "${rsync_options[@]}" "$LOCAL_ROOT/" "$REMOTE_HOST:$REMOTE_ROOT/"
	echo "ドライランが完了しました。反映する場合は--applyを指定してください。"
	exit 0
fi

leave_maintenance_on_failure() {
	local exit_status=$?
	if (( exit_status != 0 )) && [[ "$maintenance_enabled" == true ]]; then
		echo "デプロイに失敗したため、MantisBTはメンテナンスモードのままです。" >&2
		echo "問題の解決後、次のファイルを削除してください: $REMOTE_ROOT/mantis_offline.php" >&2
	fi
}
trap leave_maintenance_on_failure EXIT

if [[ "$maintenance" == true ]]; then
	echo "MantisBTをメンテナンスモードに切り替えています..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" <<'REMOTE_MAINTENANCE_ON'
set -eu
remote_root=$1
if [ -e "$remote_root/mantis_offline.php" ]; then
	echo "メンテナンス用ファイルが既に存在するため、上書きせずに中止します。" >&2
	exit 1
fi
cp "$remote_root/mantis_offline.php.sample" "$remote_root/mantis_offline.php"
REMOTE_MAINTENANCE_ON
	maintenance_enabled=true
fi

echo "$LOCAL_ROOT/ を $REMOTE_HOST:$REMOTE_ROOT/ へ同期しています。"
rsync "${rsync_options[@]}" "$LOCAL_ROOT/" "$REMOTE_HOST:$REMOTE_ROOT/"

if [[ "$run_composer" == true ]]; then
	echo "本番用のComposer依存パッケージをインストールしています..."
	ssh "$REMOTE_HOST" bash -s -- \
		"$REMOTE_ROOT" "$REMOTE_COMPOSER_PHP" "$REMOTE_COMPOSER" <<'REMOTE_COMPOSER_INSTALL'
set -eu
remote_root=$1
remote_composer_php=$2
remote_composer=$3
"$remote_composer_php" "$remote_composer" install \
	--working-dir="$remote_root" \
	--no-dev \
	--no-interaction \
	--no-progress \
	--prefer-dist \
	--optimize-autoloader
REMOTE_COMPOSER_INSTALL
fi

if [[ "$upgrade_database" == true ]]; then
	echo "MantisBTのデータベーススキーマを更新しています..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" "$REMOTE_PHP" <<'REMOTE_DATABASE_UPGRADE'
set -eu
remote_root=$1
remote_php=$2
cd "$remote_root"
"$remote_php" -r '
	$_GET["mbadmin"] = 1;
	require "admin/upgrade_unattended.php";
'
REMOTE_DATABASE_UPGRADE
fi

if [[ "$maintenance_enabled" == true ]]; then
	echo "MantisBTのメンテナンスモードを解除しています..."
	ssh "$REMOTE_HOST" bash -s -- "$REMOTE_ROOT" <<'REMOTE_MAINTENANCE_OFF'
set -eu
remote_root=$1
rm -f "$remote_root/mantis_offline.php"
REMOTE_MAINTENANCE_OFF
	maintenance_enabled=false
fi

echo "本番環境へのデプロイが正常に完了しました。"
