DO $$
#variable_conflict use_column
<<block>>
DECLARE
	report_id integer := 1;
	report jsonb;
	previous_report_version_id integer;
	new_report_version_id integer;
	new_datum_id integer;
BEGIN
	SET search_path TO exports, base, public;

	CREATE TEMPORARY VIEW summary AS (
		SELECT
			ses.*,
			dense_rank() OVER (PARTITION BY event_type, package ORDER BY ses.created_at DESC) as rank
		FROM schedy_execution_summary ses);

	SELECT
		jsonb_object_agg(
			p.package,
			(SELECT
				jsonb_object_agg(
					levels.level,
					(SELECT
						jsonb_object_agg(
							tc.test_case,
							(SELECT
								jsonb_object_agg(
									ex.created_at,
									(SELECT
										jsonb_build_object(
											'executed', sum(executed),
											'passed', sum(passed)
										)
									FROM schedy_execution_summary exs
									WHERE exs.created_at = ex.created_at AND exs.package = p.package AND exs.event_type = levels.level AND exs.test_case = tc.test_case)
								)
							FROM
								(
									SELECT DISTINCT sm.created_at
									FROM summary sm
									WHERE sm.rank <= levels.cols AND sm.event_type = levels.level AND sm.package = p.package
								) AS ex
							)
						)
					FROM
						(
							SELECT DISTINCT test_case
							FROM summary sm
							WHERE sm.rank <= levels.cols AND sm.event_type = levels.level AND sm.package = p.package
						) AS tc
					)
				)
			FROM (VALUES ('nightly',20)) AS levels(level, cols)
			)
		)
	FROM (SELECT DISTINCT package FROM schedy_execution_summary WHERE created_at > now() - '2 months'::interval) p
	INTO report;

	PERFORM FROM reports WHERE id = report_id FOR UPDATE;

	SELECT id FROM report_versions WHERE report_id = report_id AND current INTO previous_report_version_id;
	INSERT INTO data (data,created_at,updated_at) VALUES (report, now(), now()) RETURNING id INTO new_datum_id;

	INSERT INTO report_versions (report_id, version, created_at, updated_at, current, projector_id, datum_id) VALUES (
		report_id,
		COALESCE((SELECT version FROM report_versions WHERE id = previous_report_version_id),0) + 1,
		now(),
		now(),
		true,
		(SELECT projector_id FROM report_versions WHERE id = previous_report_version_id),
		new_datum_id
	) RETURNING id INTO new_report_version_id;

	UPDATE report_versions SET current = false, updated_at = now() WHERE id = previous_report_version_id;

	INSERT INTO seapig_dependencies (name,current_version,created_at,updated_at)
	VALUES ('ReportVersion-Report#' || report_id::text, nextval('seapig_dependency_version_seq'), now(), now())
	ON CONFLICT (name) DO UPDATE SET current_version = EXCLUDED.current_version, updated_at = EXCLUDED.updated_at;

	NOTIFY seapig_dependency_changed;
END $$;
