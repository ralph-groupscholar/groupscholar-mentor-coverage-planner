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
