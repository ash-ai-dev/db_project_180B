-- Smart Campus Resource Management - Schema Creation
-- Extract from Jupyter notebook Cell 2

DROP SCHEMA IF EXISTS timetable CASCADE;
CREATE SCHEMA timetable;
SET search_path = timetable;

CREATE TABLE rooms (
  room_id text PRIMARY KEY,
  capacity integer,
  location_x integer,
  location_y integer,
  has_constraints boolean
);

CREATE TABLE room_sharing_patterns (
  room_id text PRIMARY KEY REFERENCES rooms(room_id),
  unit_slots integer,
  free_for_all_char text,
  not_available_char text,
  pattern_text text
);

CREATE TABLE room_sharing_departments (
  room_id text REFERENCES rooms(room_id),
  digit_char text,
  department_id text,
  PRIMARY KEY (room_id, digit_char, department_id)
);

CREATE TABLE classes (
  class_id text PRIMARY KEY,
  offering_id text,
  config_id  text,
  subpart_id text,
  committed boolean,
  class_limit integer,
  scheduler integer,
  dates_mask text
);

CREATE TABLE class_instructors (
  class_id text REFERENCES classes(class_id),
  instructor_id text,
  PRIMARY KEY (class_id, instructor_id)
);

CREATE TABLE class_room_options (
  class_id text REFERENCES classes(class_id),
  room_id  text REFERENCES rooms(room_id),
  pref double precision,
  PRIMARY KEY (class_id, room_id)
);

CREATE TABLE class_time_options (
  class_id text REFERENCES classes(class_id),
  days_mask text,
  start_slot integer,
  length_slots integer,
  pref  double precision,
  PRIMARY KEY (class_id, days_mask, start_slot, length_slots)
);

CREATE TABLE constraints (
  pk integer PRIMARY KEY,
  external_id text,
  type text,
  pref_raw text,
  pref_numeric double precision
);

CREATE TABLE constraint_classes (
  constraint_pk integer REFERENCES constraints(pk),
  order_index integer,
  class_id text REFERENCES classes(class_id),
  PRIMARY KEY (constraint_pk, order_index)
);

CREATE TABLE students (
  student_id text PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS instructors (
  instructor_id VARCHAR(50) PRIMARY KEY
);

CREATE TABLE student_offerings (
  student_id  text REFERENCES students(student_id),
  offering_id text,
  weight  double precision,
  PRIMARY KEY (student_id, offering_id)
);

CREATE TABLE student_classes (
  student_id text REFERENCES students(student_id),
  class_id text REFERENCES classes(class_id),
  PRIMARY KEY (student_id, class_id)
);

CREATE TABLE student_prohibited_classes (
  student_id text REFERENCES students(student_id),
  class_id text REFERENCES classes(class_id),
  PRIMARY KEY (student_id, class_id)
);

-- Verify tables were created
SELECT 'Schema created successfully!' AS status;
