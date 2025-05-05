CREATE SCHEMA IF NOT EXISTS mentor_coverage_planner;

CREATE TABLE IF NOT EXISTS mentor_coverage_planner.mentors (
    id SERIAL PRIMARY KEY,
    full_name TEXT NOT NULL,
    timezone TEXT NOT NULL,
    max_sessions_per_week INTEGER NOT NULL DEFAULT 4,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mentor_coverage_planner.coverage_blocks (
    id SERIAL PRIMARY KEY,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    coverage_type TEXT NOT NULL,
    notes TEXT,
    total_needed INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mentor_coverage_planner.assignments (
    id SERIAL PRIMARY KEY,
    mentor_id INTEGER NOT NULL REFERENCES mentor_coverage_planner.mentors(id),
    block_id INTEGER NOT NULL REFERENCES mentor_coverage_planner.coverage_blocks(id),
    status TEXT NOT NULL DEFAULT 'pending',
    priority SMALLINT NOT NULL DEFAULT 1,
    last_contacted DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (mentor_id, block_id)
);

CREATE OR REPLACE VIEW mentor_coverage_planner.coverage_summary AS
SELECT b.day_of_week,
       CASE b.day_of_week
            WHEN 0 THEN 'Sun'
            WHEN 1 THEN 'Mon'
            WHEN 2 THEN 'Tue'
            WHEN 3 THEN 'Wed'
            WHEN 4 THEN 'Thu'
            WHEN 5 THEN 'Fri'
            WHEN 6 THEN 'Sat'
       END AS day_label,
       b.start_time,
       b.end_time,
       b.total_needed,
       COUNT(a.id) FILTER (WHERE a.status = 'confirmed') AS confirmed_count,
       COUNT(a.id) FILTER (WHERE a.status IN ('pending', 'proposed')) AS pending_count
  FROM mentor_coverage_planner.coverage_blocks b
  LEFT JOIN mentor_coverage_planner.assignments a ON a.block_id = b.id
 GROUP BY b.day_of_week, b.start_time, b.end_time, b.total_needed
 ORDER BY b.day_of_week, b.start_time;

CREATE OR REPLACE VIEW mentor_coverage_planner.coverage_gaps AS
SELECT day_of_week,
       day_label,
       start_time,
       end_time,
       total_needed,
       confirmed_count,
       pending_count,
       GREATEST(total_needed - confirmed_count, 0) AS remaining_needed,
       CASE
            WHEN total_needed = 0 THEN 0
            ELSE ROUND((confirmed_count::numeric / total_needed) * 100, 1)
       END AS confirmed_pct,
       CASE
            WHEN total_needed - confirmed_count <= 0 THEN 'Covered'
            WHEN pending_count = 0 THEN 'Unassigned'
            ELSE 'Needs Follow-up'
       END AS gap_status
  FROM mentor_coverage_planner.coverage_summary
 ORDER BY day_of_week, start_time;

CREATE OR REPLACE VIEW mentor_coverage_planner.followup_queue AS
SELECT m.full_name AS mentor,
       CASE b.day_of_week
            WHEN 0 THEN 'Sun'
            WHEN 1 THEN 'Mon'
            WHEN 2 THEN 'Tue'
            WHEN 3 THEN 'Wed'
            WHEN 4 THEN 'Thu'
            WHEN 5 THEN 'Fri'
            WHEN 6 THEN 'Sat'
       END AS day,
       to_char(b.start_time, 'HH24:MI') AS start_time,
       to_char(b.end_time, 'HH24:MI') AS end_time,
       b.coverage_type,
       a.status,
       a.priority,
       a.last_contacted,
       COALESCE((CURRENT_DATE - a.last_contacted), 999) AS days_since_contact,
       CASE
            WHEN a.last_contacted IS NULL THEN 'Needs outreach'
            WHEN (CURRENT_DATE - a.last_contacted) >= 7 THEN 'Overdue'
            WHEN (CURRENT_DATE - a.last_contacted) >= 3 THEN 'Follow-up'
            ELSE 'Recent'
       END AS followup_status
  FROM mentor_coverage_planner.assignments a
  JOIN mentor_coverage_planner.mentors m ON m.id = a.mentor_id
  JOIN mentor_coverage_planner.coverage_blocks b ON b.id = a.block_id
 WHERE a.status IN ('pending', 'proposed')
 ORDER BY
       CASE
            WHEN a.last_contacted IS NULL THEN 3
            WHEN (CURRENT_DATE - a.last_contacted) >= 7 THEN 2
            WHEN (CURRENT_DATE - a.last_contacted) >= 3 THEN 1
            ELSE 0
       END DESC,
       days_since_contact DESC,
       a.priority DESC,
       m.full_name;

CREATE OR REPLACE VIEW mentor_coverage_planner.mentor_capacity AS
WITH counts AS (
    SELECT m.id,
           m.full_name AS mentor,
           m.max_sessions_per_week,
           COUNT(a.id) FILTER (WHERE a.status = 'confirmed') AS confirmed_assignments,
           COUNT(a.id) FILTER (WHERE a.status = 'pending') AS pending_assignments,
           COUNT(a.id) FILTER (WHERE a.status = 'proposed') AS proposed_assignments,
           COUNT(a.id) FILTER (WHERE a.status IN ('confirmed', 'pending', 'proposed')) AS total_assignments
      FROM mentor_coverage_planner.mentors m
      LEFT JOIN mentor_coverage_planner.assignments a ON a.mentor_id = m.id
     WHERE m.active = TRUE
     GROUP BY m.id, m.full_name, m.max_sessions_per_week
)
SELECT mentor,
       max_sessions_per_week,
       confirmed_assignments,
       pending_assignments,
       proposed_assignments,
       total_assignments,
       GREATEST(max_sessions_per_week - confirmed_assignments, 0) AS remaining_capacity,
       CASE
            WHEN max_sessions_per_week = 0 THEN 0
            ELSE ROUND((total_assignments::numeric / max_sessions_per_week) * 100, 1)
       END AS utilization_pct,
       CASE
            WHEN total_assignments > max_sessions_per_week THEN 'Overbooked'
            WHEN total_assignments = max_sessions_per_week THEN 'At Capacity'
            WHEN total_assignments >= GREATEST(max_sessions_per_week - 1, 0) THEN 'Near Capacity'
            ELSE 'Available'
       END AS capacity_status
  FROM counts
 ORDER BY
       CASE
            WHEN total_assignments > max_sessions_per_week THEN 3
            WHEN total_assignments = max_sessions_per_week THEN 2
            WHEN total_assignments >= GREATEST(max_sessions_per_week - 1, 0) THEN 1
            ELSE 0
       END DESC,
       utilization_pct DESC,
       mentor;

CREATE OR REPLACE VIEW mentor_coverage_planner.block_priority AS
WITH block_rollup AS (
    SELECT b.id,
           b.day_of_week,
           CASE b.day_of_week
                WHEN 0 THEN 'Sun'
                WHEN 1 THEN 'Mon'
                WHEN 2 THEN 'Tue'
                WHEN 3 THEN 'Wed'
                WHEN 4 THEN 'Thu'
                WHEN 5 THEN 'Fri'
                WHEN 6 THEN 'Sat'
           END AS day_label,
           b.start_time,
           b.end_time,
           b.coverage_type,
           b.total_needed,
           COUNT(a.id) FILTER (WHERE a.status = 'confirmed') AS confirmed_count,
           COUNT(a.id) FILTER (WHERE a.status IN ('pending', 'proposed')) AS pending_count,
           COUNT(a.id) FILTER (
                WHERE a.status IN ('pending', 'proposed')
                  AND (a.last_contacted IS NULL OR (CURRENT_DATE - a.last_contacted) >= 7)
           ) AS overdue_contacts,
           COUNT(a.id) FILTER (
                WHERE a.status IN ('pending', 'proposed')
                  AND (a.last_contacted IS NULL OR (CURRENT_DATE - a.last_contacted) >= 3)
           ) AS followup_needed
      FROM mentor_coverage_planner.coverage_blocks b
      LEFT JOIN mentor_coverage_planner.assignments a ON a.block_id = b.id
     GROUP BY b.id, b.day_of_week, b.start_time, b.end_time, b.coverage_type, b.total_needed
)
SELECT day_label,
       to_char(start_time, 'HH24:MI') AS start_time,
       to_char(end_time, 'HH24:MI') AS end_time,
       coverage_type,
       total_needed,
       confirmed_count,
       pending_count,
       GREATEST(total_needed - confirmed_count, 0) AS remaining_needed,
       overdue_contacts,
       followup_needed,
       CASE
            WHEN total_needed = 0 THEN 0
            ELSE ROUND((GREATEST(total_needed - confirmed_count, 0)::numeric / total_needed) * 100, 1)
       END AS gap_pct,
       CASE
            WHEN GREATEST(total_needed - confirmed_count, 0) <= 0 THEN 'Covered'
            WHEN overdue_contacts > 0 THEN 'High'
            WHEN followup_needed > 0 THEN 'Medium'
            ELSE 'Low'
       END AS priority_status,
       ROUND(
            (GREATEST(total_needed - confirmed_count, 0) * 2)
            + overdue_contacts
            + (followup_needed * 0.5),
            1
       ) AS priority_score
  FROM block_rollup
 ORDER BY
       CASE
            WHEN GREATEST(total_needed - confirmed_count, 0) <= 0 THEN 0
            WHEN overdue_contacts > 0 THEN 3
            WHEN followup_needed > 0 THEN 2
            ELSE 1
       END DESC,
       priority_score DESC,
       day_of_week,
       start_time;
