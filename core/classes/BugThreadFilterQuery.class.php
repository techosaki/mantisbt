<?php
# MantisBT - A PHP based bugtracking system
# Licensed under the GNU General Public License, version 2 or later.

/**
 * Thread list ordering, applied before pagination without changing View Issues.
 */
class BugThreadFilterQuery extends BugFilterQuery {

	protected function build_order_by() {
		# Honor explicit sort choices; keep the established thread order for the
		# default "last updated descending" selection.
		if( $this->filter[FILTER_PROPERTY_SORT_FIELD_NAME] !== 'last_updated'
			|| $this->filter[FILTER_PROPERTY_SORT_DIRECTION] !== 'DESC' ) {
			parent::build_order_by();
			return;
		}

		if( gpc_string_to_bool( $this->filter[FILTER_PROPERTY_STICKY] ) && $this->use_sticky ) {
			$this->add_order( '{bug}.sticky DESC' );
		}

		# Urgent and immediate issues form a single group, ordered by latest note.
		$this->add_select( 'CASE WHEN {bug}.priority IN (' . URGENT . ', ' . IMMEDIATE
			. ') THEN 0 ELSE 1 END AS thread_priority_group' );
		$this->add_order( 'thread_priority_group ASC' );

		# Match note visibility across projects, including the user's own private notes.
		$t_projects = $this->helper_filter_projects_using_access( 'private_bugnote_threshold' );
		$t_visibility = '';
		if( ALL_PROJECTS !== $t_projects ) {
			$t_visibility = ' AND (thread_note.view_state = ' . $this->param( VS_PUBLIC )
				. ' OR thread_note.reporter_id = ' . $this->param( $this->user_id );
			if( !empty( $t_projects ) ) {
				$t_visibility .= ' OR ' . $this->sql_in( '{bug}.project_id', $t_projects );
			}
			$t_visibility .= ')';
		}
		# New issues without notes use their creation date, never their update date.
		$this->add_select( 'COALESCE((SELECT MAX(thread_note.date_submitted)'
			. ' FROM {bugnote} thread_note WHERE thread_note.bug_id = {bug}.id'
			. $t_visibility . '), {bug}.date_submitted) AS thread_latest_note' );
		$this->add_order( 'thread_latest_note DESC' );
		$this->add_order( '{bug}.id DESC' );
	}
}
