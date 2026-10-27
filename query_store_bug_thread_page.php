<?php
# MantisBT - A PHP based bugtracking system
# Licensed under the GNU General Public License, version 2 or later.

require_once( 'core.php' );
require_api( 'bug_thread_filter_api.php' );

# Keep the standard save form, permission checks and CSRF token intact.
ob_start();
include( __DIR__ . '/query_store_page.php' );
echo bug_thread_filter_rewrite_urls( ob_get_clean() );
