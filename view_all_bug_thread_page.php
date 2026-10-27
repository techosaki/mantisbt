<?php
# MantisBT - A PHP based bugtracking system
# Licensed under the GNU General Public License, version 2 or later.

require_once( 'core.php' );
require_api( 'access_api.php' );
require_api( 'authentication_api.php' );
require_api( 'bugnote_api.php' );
require_api( 'bug_thread_filter_api.php' );
require_api( 'compress_api.php' );
require_api( 'filter_api.php' );
require_api( 'gpc_api.php' );
require_api( 'html_api.php' );
require_api( 'lang_api.php' );
require_api( 'print_api.php' );
require_api( 'project_api.php' );
require_api( 'string_api.php' );
require_api( 'user_api.php' );

require_js( 'bugFilter.js' );
require_css( 'status_config.php' );

auth_ensure_user_authenticated();

$f_page_number = max( 1, gpc_get_int( 'page_number', 1 ) );
$t_project_id = gpc_get_int( 'project_id', helper_get_current_project() );
if( ( ALL_PROJECTS == $t_project_id || project_exists( $t_project_id ) )
	&& $t_project_id != helper_get_current_project() ) {
	helper_set_current_project( $t_project_id );
	print_header_redirect( $_SERVER['REQUEST_URI'], false, true );
}

# Use the same validated filter for the controls, query and pagination.
$t_filter = filter_ensure_valid_filter( filter_get_bug_rows_filter() );
$t_page_count = 0;
$t_bug_count = 0;
# Sort the complete filtered result before limiting it to the requested page.
$t_query = new BugThreadFilterQuery( $t_filter, array( 'use_sticky' => true ) );
$t_bug_count = $t_query->get_bug_count();
$t_per_page = max( 1, filter_per_page( $t_filter, $t_bug_count, null ) );
$t_page_count = filter_page_count( $t_bug_count, $t_per_page );
$f_page_number = filter_valid_page_number( $f_page_number, $t_page_count );
$t_query->set_limit( $t_per_page );
$t_query->set_offset( filter_offset( $f_page_number, $t_per_page ) );
$t_rows = $t_bug_count ? $t_query->fetch_all() : array();
$t_rows = filter_cache_result( $t_rows, array_column( $t_rows, 'id' ) );

require_css( 'bug_threads.css' );
compress_enable();
html_robots_noindex();
layout_page_header( lang_get( 'view_bug_threads_link' ) );
layout_page_begin( __FILE__ );
bug_thread_filter_draw_selection_area();
?>
<div class="col-md-12 col-xs-12">
	<h1 class="header smaller lighter"><?php echo lang_get( 'view_bug_threads_link' ) ?></h1>
	<p><?php echo lang_get( 'bug_threads_description' ) ?></p>
	<p><a href="view_all_bug_page.php"><?php echo lang_get( 'view_bugs_link' ) ?></a>
		<span class="badge"><?php echo $t_bug_count ?></span></p>
<?php
if( !$t_rows ) {
	echo '<p class="alert alert-info">' . lang_get( 'bug_threads_empty' ) . '</p>';
}

foreach( $t_rows as $t_bug ) {
	# Match the issue detail page's project-specific permission settings,
	# including when the list contains issues from multiple projects.
	$t_previous_project_override = $g_project_override;
	$g_project_override = $t_bug->project_id;
	try {
		if( !access_has_bug_level( config_get( 'view_bug_threshold' ), $t_bug->id ) ) {
			continue;
		}
		$t_notes = bugnote_get_all_visible_bugnotes( $t_bug->id, 'ASC', 0 );
		$t_older_count = max( 0, count( $t_notes ) - 5 );
		$t_note_groups = array(
			array_slice( $t_notes, 0, $t_older_count ),
			array_slice( $t_notes, $t_older_count )
		);
		user_cache_array_rows( array_unique( array_column( $t_notes, 'reporter_id' ) ) );
		$t_date_format = config_get( 'normal_date_format' );
?>
	<section class="widget-box widget-color-blue2 bug-thread" aria-labelledby="thread-<?php echo $t_bug->id ?>">
		<div class="widget-header widget-header-small">
			<h2 class="widget-title lighter" id="thread-<?php echo $t_bug->id ?>">
				<a href="<?php echo string_get_bug_view_url( $t_bug->id ) ?>">
					<?php echo bug_format_id( $t_bug->id ) . ': ' . string_display_line( $t_bug->summary ) ?>
				</a>
			</h2>
		</div>
		<div class="widget-body"><div class="widget-main">
			<p class="bug-thread-meta">
				<?php echo string_display_line( project_get_name( $t_bug->project_id ) ) ?>
				/ <?php echo get_enum_element( 'status', $t_bug->status ) ?>
				/ <?php echo lang_get( 'updated' ) . ': ' . date( $t_date_format, $t_bug->last_updated ) ?>
			</p>
<?php
		foreach( $t_note_groups as $t_group_index => $t_group ) {
			if( !$t_group ) {
				continue;
			}
			if( $t_group_index === 0 ) {
				echo '<details class="bug-thread-older"><summary>'
					. sprintf( lang_get( 'bug_threads_older_notes' ), $t_older_count )
					. '</summary>';
			}
			foreach( $t_group as $t_note ) {
?>
			<article class="bug-thread-note" id="c<?php echo $t_note->id ?>">
				<div class="bug-thread-note-meta">
					<strong><?php print_user( $t_note->reporter_id ) ?></strong>
					<small><?php echo date( $t_date_format, $t_note->date_submitted ) ?></small>
					<a rel="bookmark" href="<?php echo string_get_bugnote_view_url( $t_bug->id, $t_note->id ) ?>">
						<?php echo string_display_line( config_get_global( 'bugnote_link_tag' ) ) . bugnote_format_id( $t_note->id ) ?>
					</a>
<?php if( $t_note->view_state == VS_PRIVATE ) { ?>
					<span class="label label-warning"><?php echo lang_get( 'private' ) ?></span>
<?php } ?>
				</div>
				<div class="bug-thread-note-body"><?php echo string_display_links( $t_note->note ) ?></div>
			</article>
<?php
			}
			if( $t_group_index === 0 ) {
				echo '</details>';
			}
		}
		if( !$t_notes ) {
			echo '<p>' . lang_get( 'no_bugnotes_msg' ) . '</p>';
		}
?>
			<a class="btn btn-primary btn-sm" href="<?php echo string_get_bug_view_url( $t_bug->id ) ?>#addbugnote">
				<?php echo lang_get( 'add_bugnote_title' ) ?>
			</a>
		</div></div>
	</section>
<?php
	} finally {
		$g_project_override = $t_previous_project_override;
	}
}
?>
	<div class="clearfix">
		<?php print_page_links( 'view_all_bug_thread_page.php', 1, $t_page_count, $f_page_number,
			filter_get_temporary_key( $t_filter ) ) ?>
	</div>
</div>
<?php
layout_page_end();
