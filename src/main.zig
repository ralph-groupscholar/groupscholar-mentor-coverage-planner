const std = @import("std");

const Query = struct {
    name: []const u8,
    sql: []const u8,
};

const queries = [_]Query{
    .{
        .name = "list-mentors",
        .sql =
        \\SELECT id,
        \\       full_name AS mentor,
        \\       timezone,
        \\       max_sessions_per_week,
        \\       active
        \\  FROM mentor_coverage_planner.mentors
        \\ ORDER BY active DESC, full_name;
    },
    .{
        .name = "list-blocks",
        .sql =
        \\SELECT id,
        \\       CASE day_of_week
        \\            WHEN 0 THEN 'Sun'
        \\            WHEN 1 THEN 'Mon'
        \\            WHEN 2 THEN 'Tue'
        \\            WHEN 3 THEN 'Wed'
        \\            WHEN 4 THEN 'Thu'
        \\            WHEN 5 THEN 'Fri'
        \\            WHEN 6 THEN 'Sat'
        \\       END AS day,
        \\       to_char(start_time, 'HH24:MI') AS start_time,
        \\       to_char(end_time, 'HH24:MI') AS end_time,
        \\       coverage_type,
        \\       COALESCE(notes, '') AS notes
        \\  FROM mentor_coverage_planner.coverage_blocks
        \\ ORDER BY day_of_week, start_time;
    },
    .{
        .name = "assignments",
        .sql =
        \\SELECT m.full_name AS mentor,
        \\       CASE b.day_of_week
        \\            WHEN 0 THEN 'Sun'
        \\            WHEN 1 THEN 'Mon'
        \\            WHEN 2 THEN 'Tue'
        \\            WHEN 3 THEN 'Wed'
        \\            WHEN 4 THEN 'Thu'
        \\            WHEN 5 THEN 'Fri'
        \\            WHEN 6 THEN 'Sat'
        \\       END AS day,
        \\       to_char(b.start_time, 'HH24:MI') AS start_time,
        \\       to_char(b.end_time, 'HH24:MI') AS end_time,
        \\       a.status,
        \\       a.priority
        \\  FROM mentor_coverage_planner.assignments a
        \\  JOIN mentor_coverage_planner.mentors m ON m.id = a.mentor_id
        \\  JOIN mentor_coverage_planner.coverage_blocks b ON b.id = a.block_id
        \\ ORDER BY b.day_of_week, b.start_time, a.priority DESC;
    },
    .{
        .name = "coverage-summary",
        .sql =
        \\SELECT day_label AS day,
        \\       to_char(start_time, 'HH24:MI') AS start_time,
        \\       to_char(end_time, 'HH24:MI') AS end_time,
        \\       confirmed_count,
        \\       pending_count,
        \\       total_needed
        \\  FROM mentor_coverage_planner.coverage_summary
        \\ ORDER BY day_of_week, start_time;
    },
    .{
        .name = "coverage-gaps",
        .sql =
        \\SELECT day_label AS day,
        \\       to_char(start_time, 'HH24:MI') AS start_time,
        \\       to_char(end_time, 'HH24:MI') AS end_time,
        \\       confirmed_count,
        \\       pending_count,
        \\       total_needed,
        \\       remaining_needed,
        \\       confirmed_pct,
        \\       gap_status
        \\  FROM mentor_coverage_planner.coverage_gaps
        \\ ORDER BY day_of_week, start_time;
    },
    .{
        .name = "followup-queue",
        .sql =
        \\SELECT mentor,
        \\       day,
        \\       start_time,
        \\       end_time,
        \\       coverage_type,
        \\       status,
        \\       priority,
        \\       last_contacted,
        \\       days_since_contact,
        \\       followup_status
        \\  FROM mentor_coverage_planner.followup_queue;
    },
    .{
        .name = "mentor-load",
        .sql =
        \\SELECT m.full_name AS mentor,
        \\       m.max_sessions_per_week,
        \\       COUNT(a.id) FILTER (WHERE a.status = 'confirmed') AS confirmed_assignments,
        \\       COUNT(a.id) FILTER (WHERE a.status IN ('pending', 'proposed')) AS pending_assignments,
        \\       GREATEST(
        \\           m.max_sessions_per_week - COUNT(a.id) FILTER (WHERE a.status = 'confirmed'),
        \\           0
        \\       ) AS remaining_capacity
        \\  FROM mentor_coverage_planner.mentors m
        \\  LEFT JOIN mentor_coverage_planner.assignments a ON a.mentor_id = m.id
        \\ WHERE m.active = TRUE
        \\ GROUP BY m.id, m.full_name, m.max_sessions_per_week
        \\ ORDER BY remaining_capacity DESC, m.full_name;
    },
    .{
        .name = "followup-queue",
        .sql =
        \\SELECT mentor,
        \\       day,
        \\       start_time,
        \\       end_time,
        \\       coverage_type,
        \\       status,
        \\       priority,
        \\       last_contacted,
        \\       days_since_contact,
        \\       followup_status
        \\  FROM mentor_coverage_planner.followup_queue;
    },
};

const Config = struct {
    host: []const u8,
    port: []const u8,
    user: []const u8,
    dbname: []const u8,
    password: []const u8,
    sslmode: []const u8,
};

fn usage(writer: anytype) !void {
    try writer.writeAll(
        \\mentor-coverage-planner
        \\
        \\Usage:
        \\  mentor-coverage-planner <command>
        \\
        \\Commands:
        \\  list-mentors       List active mentors and weekly capacity.
        \\  list-blocks        List coverage blocks by day/time.
        \\  assignments        List current mentor assignments.
        \\  coverage-summary   Summarize confirmed vs pending coverage.
        \\  coverage-gaps      Show blocks with remaining confirmed gaps.
        \\  followup-queue     Show pending/proposed assignments needing outreach.
        \\  mentor-load        Summarize confirmed vs pending load by mentor.
        \\
        \\Environment variables:
        \\  GS_DB_HOST       (default: db-acupinir.groupscholar.com)
        \\  GS_DB_PORT       (default: 23947)
        \\  GS_DB_USER       (default: ralph)
        \\  GS_DB_PASSWORD   (required)
        \\  GS_DB_NAME       (default: postgres)
        \\  GS_DB_SSLMODE    (default: require)
    );
}

fn getEnvOrDefault(alloc: std.mem.Allocator, key: []const u8, fallback: []const u8) ![]const u8 {
    const value = std.process.getEnvVarOwned(alloc, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return fallback,
        else => return err,
    };
    return value;
}

fn loadConfig(alloc: std.mem.Allocator) !Config {
    const host = try getEnvOrDefault(alloc, "GS_DB_HOST", "db-acupinir.groupscholar.com");
    const port = try getEnvOrDefault(alloc, "GS_DB_PORT", "23947");
    const user = try getEnvOrDefault(alloc, "GS_DB_USER", "ralph");
    const dbname = try getEnvOrDefault(alloc, "GS_DB_NAME", "postgres");
    const sslmode = try getEnvOrDefault(alloc, "GS_DB_SSLMODE", "require");

    const password = std.process.getEnvVarOwned(alloc, "GS_DB_PASSWORD") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.MissingPassword,
        else => return err,
    };

    return .{
        .host = host,
        .port = port,
        .user = user,
        .dbname = dbname,
        .password = password,
        .sslmode = sslmode,
    };
}

fn connectionString(alloc: std.mem.Allocator, cfg: Config) ![]const u8 {
    return try std.fmt.allocPrint(
        alloc,
        "host={s} port={s} user={s} dbname={s} sslmode={s}",
        .{ cfg.host, cfg.port, cfg.user, cfg.dbname, cfg.sslmode },
    );
}

fn runQuery(alloc: std.mem.Allocator, cfg: Config, sql: []const u8) !void {
    const conn = try connectionString(alloc, cfg);
    defer alloc.free(conn);

    var argv = std.ArrayList([]const u8).init(alloc);
    defer argv.deinit();

    try argv.appendSlice(&[_][]const u8{
        "psql",
        "-P",
        "pager=off",
        "-P",
        "footer=off",
        "-P",
        "format=aligned",
        "-d",
        conn,
        "-c",
        sql,
    });

    var proc = std.process.Child.init(argv.items, alloc);
    proc.stdin_behavior = .Close;
    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    proc.env_map = std.process.EnvMap.init(alloc);
    try proc.env_map.?.put("PGPASSWORD", cfg.password);
    try proc.env_map.?.put("PGCONNECT_TIMEOUT", "5");

    const result = try proc.spawnAndWait();

    const stdout = proc.stdout.?.readToEndAlloc(alloc, 1024 * 64) catch &[_]u8{};
    const stderr = proc.stderr.?.readToEndAlloc(alloc, 1024 * 16) catch &[_]u8{};
    defer alloc.free(stdout);
    defer alloc.free(stderr);

    switch (result) {
        .Exited => |code| if (code != 0) {
            try std.io.getStdErr().writer().writeAll(stderr);
            return error.QueryFailed;
        },
        else => return error.QueryFailed,
    }

    try std.io.getStdOut().writer().writeAll(stdout);
}

fn findQuery(name: []const u8) ?Query {
    for (queries) |query| {
        if (std.mem.eql(u8, query.name, name)) return query;
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        try usage(std.io.getStdErr().writer());
        return;
    }

    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        try usage(std.io.getStdOut().writer());
        return;
    }

    const query = findQuery(args[1]) orelse {
        try std.io.getStdErr().writer().print("Unknown command: {s}\n\n", .{args[1]});
        try usage(std.io.getStdErr().writer());
        return;
    };

    const cfg = loadConfig(alloc) catch |err| {
        if (err == error.MissingPassword) {
            try std.io.getStdErr().writer().writeAll("GS_DB_PASSWORD is required.\n");
            return;
        }
        return err;
    };

    try runQuery(alloc, cfg, query.sql);
}

test "connectionString builds expected format" {
    const alloc = std.testing.allocator;
    const cfg = Config{
        .host = "host",
        .port = "5432",
        .user = "user",
        .dbname = "db",
        .password = "secret",
        .sslmode = "require",
    };
    const conn = try connectionString(alloc, cfg);
    defer alloc.free(conn);
    try std.testing.expect(std.mem.eql(u8, conn, "host=host port=5432 user=user dbname=db sslmode=require"));
}

test "findQuery locates followup queue" {
    const query = findQuery("followup-queue") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.eql(u8, query.name, "followup-queue"));
    try std.testing.expect(std.mem.containsAtLeast(u8, query.sql, 1, "followup_queue"));
}

test "findQuery locates coverage gaps" {
    const query = findQuery("coverage-gaps") orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, query.name, "coverage-gaps"));
}

test "findQuery locates followup queue" {
    const query = findQuery("followup-queue") orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, query.name, "followup-queue"));
}
