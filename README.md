# Group Scholar Mentor Coverage Planner

A Zig CLI that tracks mentor coverage blocks, assignments, and weekly gaps for Group Scholar. It reads from the production PostgreSQL database and outputs aligned tables for ops planning.

## Features
- List mentors and weekly capacity.
- Review coverage blocks by day and focus area.
- Summarize confirmed vs pending coverage needs.
- Inspect current mentor assignments.

## Tech Stack
- Zig
- PostgreSQL (via `psql` command line client)

## Getting Started

### Prerequisites
- Zig (0.11+ recommended)
- `psql` available on your PATH

### Build
```
zig build
```

### Run
```
GS_DB_PASSWORD=... zig build run -- list-mentors
```

### Environment Variables
- `GS_DB_HOST` (default: `db-acupinir.groupscholar.com`)
- `GS_DB_PORT` (default: `23947`)
- `GS_DB_USER` (default: `ralph`)
- `GS_DB_PASSWORD` (required)
- `GS_DB_NAME` (default: `postgres`)
- `GS_DB_SSLMODE` (default: `require`)

## Database Setup

Run schema and seed data against production:
```
PGPASSWORD="$GS_DB_PASSWORD" psql "host=$GS_DB_HOST port=$GS_DB_PORT user=$GS_DB_USER dbname=$GS_DB_NAME" -f scripts/schema.sql
PGPASSWORD="$GS_DB_PASSWORD" psql "host=$GS_DB_HOST port=$GS_DB_PORT user=$GS_DB_USER dbname=$GS_DB_NAME" -f scripts/seed.sql
```

## Testing
```
zig build test
```
