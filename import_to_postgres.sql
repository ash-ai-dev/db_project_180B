-- ========================================
-- Smart Campus Resource Management
-- PostgreSQL Database Schema & Import
-- ========================================

-- Drop existing tables if they exist (in reverse dependency order)
DROP TABLE IF EXISTS student_prohibited_classes CASCADE;
DROP TABLE IF EXISTS student_classes CASCADE;
DROP TABLE IF EXISTS student_offerings CASCADE;
DROP TABLE IF EXISTS constraint_classes CASCADE;
DROP TABLE IF EXISTS class_time_options CASCADE;
DROP TABLE IF EXISTS class_room_options CASCADE;
DROP TABLE IF EXISTS class_instructors CASCADE;
DROP TABLE IF EXISTS room_sharing_departments CASCADE;
DROP TABLE IF EXISTS room_sharing_patterns CASCADE;
DROP TABLE IF EXISTS constraints CASCADE;
DROP TABLE IF EXISTS students CASCADE;
DROP TABLE IF EXISTS classes CASCADE;
DROP TABLE IF EXISTS instructors CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;

-- ========================================
-- TABLE CREATION
-- ========================================

-- Rooms: Physical classroom spaces
CREATE TABLE rooms (
    room_id VARCHAR(100) PRIMARY KEY,
    capacity INTEGER,
    location_x INTEGER,
    location_y INTEGER,
    has_constraints BOOLEAN
);

-- Room Sharing Patterns: Time-based room availability
CREATE TABLE room_sharing_patterns (
    room_id VARCHAR(100) REFERENCES rooms(room_id) ON DELETE CASCADE,
    unit_slots INTEGER,
    free_for_all_char VARCHAR(5),
    not_available_char VARCHAR(5),
    pattern_text TEXT,
    PRIMARY KEY (room_id)
);

-- Room Sharing Departments: Which departments can use each room
CREATE TABLE room_sharing_departments (
    room_id VARCHAR(100) REFERENCES rooms(room_id) ON DELETE CASCADE,
    digit_char VARCHAR(5),
    department_id VARCHAR(100),
    PRIMARY KEY (room_id, department_id)
);

-- Instructors: Teaching staff
CREATE TABLE instructors (
    instructor_id VARCHAR(100) PRIMARY KEY
);

-- Classes: Course sections
CREATE TABLE classes (
    class_id VARCHAR(100) PRIMARY KEY,
    offering_id VARCHAR(100),
    config_id VARCHAR(100),
    subpart_id VARCHAR(100),
    committed BOOLEAN,
    class_limit INTEGER,
    scheduler INTEGER,
    dates_mask TEXT
);

-- Class Instructors: Which instructors teach which classes
CREATE TABLE class_instructors (
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    instructor_id VARCHAR(100) REFERENCES instructors(instructor_id) ON DELETE CASCADE,
    PRIMARY KEY (class_id, instructor_id)
);

-- Class Room Options: Preferred/possible rooms for each class
CREATE TABLE class_room_options (
    id SERIAL PRIMARY KEY,
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    room_id VARCHAR(100) REFERENCES rooms(room_id) ON DELETE CASCADE,
    pref REAL
);

-- Class Time Options: Preferred/possible time slots for each class
CREATE TABLE class_time_options (
    id SERIAL PRIMARY KEY,
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    days_mask VARCHAR(50),
    start_slot INTEGER,
    length_slots INTEGER,
    pref REAL
);

-- Constraints: Scheduling rules and restrictions
CREATE TABLE constraints (
    pk INTEGER PRIMARY KEY,
    external_id VARCHAR(100),
    type VARCHAR(100),
    pref_raw VARCHAR(50),
    pref_numeric REAL
);

-- Constraint Classes: Which classes are affected by each constraint
CREATE TABLE constraint_classes (
    constraint_pk INTEGER REFERENCES constraints(pk) ON DELETE CASCADE,
    order_index INTEGER,
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    PRIMARY KEY (constraint_pk, class_id)
);

-- Students: Student records
CREATE TABLE students (
    student_id VARCHAR(100) PRIMARY KEY
);

-- Student Offerings: Which course offerings students want
CREATE TABLE student_offerings (
    id SERIAL PRIMARY KEY,
    student_id VARCHAR(100) REFERENCES students(student_id) ON DELETE CASCADE,
    offering_id VARCHAR(100),
    weight REAL
);

-- Student Classes: Specific class sections students are enrolled in
CREATE TABLE student_classes (
    student_id VARCHAR(100) REFERENCES students(student_id) ON DELETE CASCADE,
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    PRIMARY KEY (student_id, class_id)
);

-- Student Prohibited Classes: Classes students cannot take
CREATE TABLE student_prohibited_classes (
    student_id VARCHAR(100) REFERENCES students(student_id) ON DELETE CASCADE,
    class_id VARCHAR(100) REFERENCES classes(class_id) ON DELETE CASCADE,
    PRIMARY KEY (student_id, class_id)
);

-- ========================================
-- DATA IMPORT (UPDATE PATH AS NEEDED)
-- ========================================

-- IMPORTANT: Update this path to match your system
-- For macOS/Linux: '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/'
-- For Windows: 'C:/Users/YourName/path/to/out_csv/'

\echo 'Importing rooms...'
\COPY rooms FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/rooms.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing instructors...'
\COPY instructors FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/instructors.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing students...'
\COPY students FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/students.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing classes...'
\COPY classes FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/classes.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing constraints...'
\COPY constraints FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/constraints.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing room sharing patterns...'
\COPY room_sharing_patterns FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/room_sharing_patterns.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing room sharing departments...'
\COPY room_sharing_departments FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/room_sharing_departments.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing class instructors...'
\COPY class_instructors FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/class_instructors.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing class room options...'
\COPY class_room_options(class_id, room_id, pref) FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/class_room_options.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing class time options...'
\COPY class_time_options(class_id, days_mask, start_slot, length_slots, pref) FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/class_time_options.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing constraint classes...'
\COPY constraint_classes FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/constraint_classes.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing student offerings...'
\COPY student_offerings(student_id, offering_id, weight) FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/student_offerings.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing student classes...'
\COPY student_classes FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/student_classes.csv' WITH (FORMAT csv, HEADER true, NULL '');

\echo 'Importing student prohibited classes...'
\COPY student_prohibited_classes FROM '/Users/tambunting/coding-projects/school/db_project_180B/out_csv/student_prohibited_classes.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ========================================
-- CREATE INDEXES FOR PERFORMANCE
-- ========================================

\echo 'Creating indexes...'

CREATE INDEX idx_classes_offering ON classes(offering_id);
CREATE INDEX idx_class_instructors_class ON class_instructors(class_id);
CREATE INDEX idx_class_instructors_instructor ON class_instructors(instructor_id);
CREATE INDEX idx_class_room_options_class ON class_room_options(class_id);
CREATE INDEX idx_class_room_options_room ON class_room_options(room_id);
CREATE INDEX idx_class_time_options_class ON class_time_options(class_id);
CREATE INDEX idx_student_offerings_student ON student_offerings(student_id);
CREATE INDEX idx_student_classes_student ON student_classes(student_id);
CREATE INDEX idx_student_classes_class ON student_classes(class_id);

-- ========================================
-- SUMMARY STATISTICS
-- ========================================

\echo ''
\echo '========================================='
\echo 'Import Complete! Database Statistics:'
\echo '========================================='

SELECT 'Rooms' AS table_name, COUNT(*) AS row_count FROM rooms
UNION ALL
SELECT 'Instructors', COUNT(*) FROM instructors
UNION ALL
SELECT 'Classes', COUNT(*) FROM classes
UNION ALL
SELECT 'Students', COUNT(*) FROM students
UNION ALL
SELECT 'Constraints', COUNT(*) FROM constraints
UNION ALL
SELECT 'Class Instructors', COUNT(*) FROM class_instructors
UNION ALL
SELECT 'Class Room Options', COUNT(*) FROM class_room_options
UNION ALL
SELECT 'Class Time Options', COUNT(*) FROM class_time_options
UNION ALL
SELECT 'Student Classes', COUNT(*) FROM student_classes;

\echo ''
\echo 'All tables created and data imported successfully!'
