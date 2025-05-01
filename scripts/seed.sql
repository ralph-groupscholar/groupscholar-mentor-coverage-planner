TRUNCATE mentor_coverage_planner.assignments RESTART IDENTITY CASCADE;
TRUNCATE mentor_coverage_planner.coverage_blocks RESTART IDENTITY CASCADE;
TRUNCATE mentor_coverage_planner.mentors RESTART IDENTITY CASCADE;

INSERT INTO mentor_coverage_planner.mentors (full_name, timezone, max_sessions_per_week, active)
VALUES
    ('Anya Patel', 'America/Chicago', 5, TRUE),
    ('Jordan Lee', 'America/New_York', 4, TRUE),
    ('Maya Torres', 'America/Los_Angeles', 3, TRUE),
    ('Elliot Wang', 'America/Denver', 4, TRUE),
    ('Sofia Njeri', 'America/New_York', 2, FALSE);

INSERT INTO mentor_coverage_planner.coverage_blocks (day_of_week, start_time, end_time, coverage_type, notes, total_needed)
VALUES
    (1, '09:00', '11:00', 'Essay Review', 'Priority for early-week turnaround', 2),
    (2, '13:00', '15:00', 'Mock Interviews', 'STEM applicants focus', 2),
    (3, '17:00', '19:00', 'Financial Aid Support', 'FAFSA changes', 1),
    (4, '12:00', '14:00', 'Application Strategy', 'First-gen scholars', 2),
    (5, '10:00', '12:00', 'Drop-in Hours', 'General advising', 1);

INSERT INTO mentor_coverage_planner.assignments (mentor_id, block_id, status, priority, last_contacted)
VALUES
    (1, 1, 'confirmed', 3, CURRENT_DATE - INTERVAL '4 days'),
    (2, 1, 'pending', 2, CURRENT_DATE - INTERVAL '2 days'),
    (3, 2, 'confirmed', 2, CURRENT_DATE - INTERVAL '7 days'),
    (4, 2, 'proposed', 1, NULL),
    (1, 4, 'confirmed', 2, CURRENT_DATE - INTERVAL '5 days'),
    (2, 5, 'pending', 1, CURRENT_DATE - INTERVAL '3 days');
