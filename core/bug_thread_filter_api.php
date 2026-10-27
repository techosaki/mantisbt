<?php
# MantisBT - A PHP based bugtracking system
# Licensed under the GNU General Public License, version 2 or later.

require_api( 'filter_api.php' );

/**
 * Reuse the standard filter widget, routing its actions back to the thread list.
 * Keep the shared renderer and the normal issue list unchanged.
 */
function bug_thread_filter_draw_selection_area() {
	ob_start();
	filter_draw_selection_area();
	$t_html = ob_get_clean();
	$t_filter = current_user_get_bug_filter();
	if( filter_is_temporary( $t_filter ) ) {
		# The non-dynamic view-type toggle also needs the temporary filter key.
		$t_html = str_replace( 'href="view_filters_page.php?view_type=',
			'href="view_filters_page.php?filter='
				. string_attribute( filter_get_temporary_key( $t_filter ) ) . '&amp;view_type=', $t_html );
	}
	echo bug_thread_filter_rewrite_urls( $t_html );
}

/**
 * Adapt only URL attributes in standard filter views, including the save form.
 */
function bug_thread_filter_rewrite_urls( $p_html ) {
	$t_routes = array(
		'view_all_set.php' => 'view_all_bug_thread_set.php',
		'view_filters_page.php' => 'view_bug_thread_filters_page.php',
		'view_all_bug_page.php' => 'view_all_bug_thread_page.php',
		'query_store_page.php' => 'query_store_bug_thread_page.php',
		'query_store.php' => 'query_store_bug_thread.php'
	);
	$t_replacements = array();
	foreach( $t_routes as $t_source => $t_target ) {
		foreach( array( 'href', 'action' ) as $t_attribute ) {
			# Only the save form's back action changes; preserve the navigation menu.
			if( $t_source === 'view_all_bug_page.php' && $t_attribute !== 'action' ) {
				continue;
			}
			foreach( array( $t_source => $t_target,
				helper_mantis_url( $t_source ) => helper_mantis_url( $t_target ) ) as $t_from => $t_to ) {
				# Match only URL attributes, never user-entered filter values.
				foreach( array( '"', '?' ) as $t_suffix ) {
					$t_replacements[$t_attribute . '="' . $t_from . $t_suffix]
						= $t_attribute . '="' . $t_to . $t_suffix;
				}
			}
		}
	}
	return strtr( $p_html, $t_replacements );
}
