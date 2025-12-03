# Smart Campus Database Project

A PostgreSQL-based database system for managing campus operations including students, courses, enrollments, and scheduling.

## Project Overview

This project implements a comprehensive database solution for a smart campus management system. It handles student records, course information, enrollments, room scheduling, and timetable management.

## Database Schema

The database (`smart`) contains the following main tables:
- **Students**: Student information and records
- **Courses**: Course catalog and details
- **Enrollments**: Student course registrations
- **Rooms**: Campus room inventory
- **Schedule**: Class scheduling and timetable

## Prerequisites

- PostgreSQL (installed and running)
- Python 3.x
- Virtual environment support

## Setup Instructions

### 1. Create Virtual Environment

```bash
python3 -m venv venv
source venv/bin/activate
```

### 2. Install Dependencies

```bash
pip install ipython-sql sqlalchemy psycopg2-binary
```

### 3. Database Setup

Create the database and run the schema:

```bash
# Create database
createdb smart

# Run SQL schema (if using test.sql)
psql -d smart -f test.sql
```

## Project Structure

```
smart-campus/
├── scripts/
│   ├── backup_pg.sh      # Database backup script
│   └── restore_pg.sh     # Database restore script
├── backups/              # Database backups (gitignored)
├── *.csv                 # Data files (gitignored)
├── test.sql              # Database schema and queries
├── venv/                 # Virtual environment (gitignored)
└── README.md             # This file
```

## Database Operations

### Backup Database

```bash
PG_NAME=smart PG_USER=shervan ./scripts/backup_pg.sh
```

This creates a timestamped backup in the `backups/` directory.

### Restore Database

```bash
PG_NAME=smart PG_USER=shervan ./scripts/restore_pg.sh backups/smart_YYYYMMDD_HHMMSS.sql
```

**Warning**: This will DROP and RECREATE the database. Type `YES` when prompted to confirm.

## Working with the Database

### Using psql (Command Line)

```bash
# Connect to database
psql -d smart

# Run SQL file
psql -d smart -f test.sql
```

### Using Jupyter Notebooks

1. Load SQL extension:
```python
import sqlalchemy
%load_ext sql
%sql postgresql://shervan@localhost/smart
```

2. Run SQL commands:
```python
%%sql
SELECT * FROM students LIMIT 10;
```

### Using VS Code

1. Install the PostgreSQL extension
2. Configure connection to `smart` database
3. Execute queries directly from `.sql` files

## Environment Variables

The backup/restore scripts support the following environment variables:

- `PG_HOST` - Database host (default: localhost)
- `PG_PORT` - Database port (default: 5432)
- `PG_NAME` - Database name (default: smart_campus)
- `PG_USER` - Database user (default: postgres)
- `PG_PASSWORD` - Database password (optional)

## Notes

- CSV data files and backups are excluded from version control for security and size reasons
- Always backup your database before major changes
- The database contains sensitive student information - handle with care
- Virtual environment dependencies are not committed - run `pip install` after cloning

## Contributors

UCSC CS 180B Database Project

## License

Educational use only