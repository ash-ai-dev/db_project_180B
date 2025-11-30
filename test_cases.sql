-- SQL Test Cases (Streamlined)

-- Total: 8 test cases covering all requirements
-- CRUD, Constraints, Scheduling, Transactions, Indexing


-- SECTION A: CRUD TEST CASE (1) --

-- TEST CASE A1: Complete CRUD operations on a room
-- Expected: Insert succeeds, update works, delete works

-- Insert
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ROOM_001', 50, 100, 200, false);

SELECT * FROM rooms WHERE room_id = 'TEST_ROOM_001';
-- Expected: 1 row with capacity=50

-- Update
-- Set TEST_ROOM_001 capacity to 60
UPDATE rooms SET capacity = 60 WHERE room_id = 'TEST_ROOM_001';
SELECT room_id, capacity FROM rooms WHERE room_id = 'TEST_ROOM_001';
-- Expected: capacity=60

-- Delete
DELETE FROM rooms WHERE room_id = 'TEST_ROOM_001';
SELECT * FROM rooms WHERE room_id = 'TEST_ROOM_001';
-- Expected: 0 rows (deleted successfully)

-- TEST CASE A2: CRUD on students and enrollments
-- Expected: Student and enrollment can be created, updated, and deleted

-- Create a test student
INSERT INTO students (student_id)
VALUES ('TEST_STUDENT_001');

-- Enroll the student in an existing class
INSERT INTO student_classes (student_id, class_id)
SELECT 'TEST_STUDENT_001', c.class_id
FROM classes c
ORDER BY c.class_id
LIMIT 1;

-- Read back student and enrollment
SELECT s.student_id, sc.class_id
FROM students s
LEFT JOIN student_classes sc USING (student_id)
WHERE s.student_id = 'TEST_STUDENT_001';

-- Update: move enrollment to (possibly) another class
UPDATE student_classes sc
SET class_id = sub.new_class_id
FROM (
    SELECT class_id AS new_class_id
    FROM classes
    ORDER BY class_id DESC
    LIMIT 1
) sub
WHERE sc.student_id = 'TEST_STUDENT_001';

-- Read back after update
SELECT s.student_id, sc.class_id
FROM students s
LEFT JOIN student_classes sc USING (student_id)
WHERE s.student_id = 'TEST_STUDENT_001';

-- Delete enrollment
DELETE FROM student_classes
WHERE student_id = 'TEST_STUDENT_001';

-- Delete student
DELETE FROM students
WHERE student_id = 'TEST_STUDENT_001';

-- Confirm cleanup
SELECT * FROM students WHERE student_id = 'TEST_STUDENT_001';
SELECT * FROM student_classes WHERE student_id = 'TEST_STUDENT_001';
-- Expected: no rows for TEST_STUDENT_001 in either table


-- SECTION B: CONSTRAINT TEST CASES (2) --

-- TEST CASE B1: Foreign key constraint violation
-- Expected: ERROR - foreign key violation on room_id

-- Try to insert class room option with nonexistent room
INSERT INTO class_room_options (class_id, room_id, pref)
VALUES ('1', 'NONEXISTENT_ROOM_999', 0.5);
-- Expected: ERROR - violates foreign key constraint
-- Each class must reference a valid room in the rooms table


-- TEST CASE B2: Primary key constraint violation
-- Expected: ERROR - duplicate key violation

-- Try to insert duplicate student
INSERT INTO students (student_id) VALUES ('1');
-- Expected: ERROR - duplicate key value violates unique constraint


-- SECTION C: SCHEDULING LOGIC TEST CASES (2) --

-- TEST CASE C1: Room demand analysis
-- Shows which rooms are most contested (scheduling conflicts)
-- Expected: List of rooms requested by multiple classes

SELECT
    cro.room_id,
    r.capacity,
    COUNT(DISTINCT cro.class_id) AS num_classes_wanting_room,
    STRING_AGG(DISTINCT cro.class_id, ', ' ORDER BY cro.class_id) AS sample_class_ids
FROM class_room_options cro
JOIN rooms r ON cro.room_id = r.room_id
GROUP BY cro.room_id, r.capacity
HAVING COUNT(DISTINCT cro.class_id) > 5
ORDER BY num_classes_wanting_room DESC
LIMIT 10;
-- Expected: Top 10 most contested rooms with class counts


-- TEST CASE C2: Time slot conflict detection
-- Identifies classes that want the same time slot
-- Expected: List of overlapping time preferences

SELECT
    cto1.class_id AS class1,
    cto2.class_id AS class2,
    cto1.days_mask,
    cto1.start_slot,
    cto1.length_slots,
    cto1.pref AS class1_pref,
    cto2.pref AS class2_pref
FROM class_time_options cto1
JOIN class_time_options cto2
    ON cto1.days_mask = cto2.days_mask
    AND cto1.start_slot = cto2.start_slot
    AND cto1.class_id < cto2.class_id  -- Avoid duplicates
WHERE cto1.pref > 0 AND cto2.pref > 0  -- Both prefer this time
LIMIT 15;
-- Expected: Pairs of classes wanting identical time slots

-- TEST CASE C3: Capacity trigger on scheduled_meetings
-- We want to see:
--   1) ERROR when room too small for class
--   2) SUCCESS when room capacity is OK
--   3) ERROR when room too big for class

SET search_path = timetable;

-- Cleanup any previous test data
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_CAP_%';
DELETE FROM classes            WHERE class_id LIKE 'TEST_CAP_%';
DELETE FROM rooms
 WHERE room_id IN (
   'TEST_ROOM_CAP_SMALL',
   'TEST_ROOM_CAP_OK',
   'TEST_ROOM_CAP_BIG'
 );

-- Create test rooms
-- SMALL:  30 seats
-- OK:     80 seats
-- BIG:   200 seats
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES
  ('TEST_ROOM_CAP_SMALL', 30,  0, 0, false),
  ('TEST_ROOM_CAP_OK',    80,  0, 0, false),
  ('TEST_ROOM_CAP_BIG',  200,  0, 0, false);

-- Create test classes
-- TOO_SMALL: limit 80  -> too big for SMALL(30)
-- OK:        limit 60  -> OK for room(80) if 60 <= 80 <= 1.5 * 60 (=90)
-- TOO_BIG:   limit 60  -> BIG(200) should be "too big"
INSERT INTO classes (class_id, class_limit)
VALUES
  ('TEST_CAP_TOO_SMALL', 80),
  ('TEST_CAP_OK',        60),
  ('TEST_CAP_TOO_BIG',   60);

-- 1) This should FAIL: room capacity < class_limit  (30 < 80)
-- INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
-- VALUES ('TEST_CAP_TOO_SMALL', 'TEST_ROOM_CAP_SMALL', 1, 100, 5, 1);
-- Expected: ERROR from enforce_capacity_ok(): capacity too small

-- 2) This should FAIL: room capacity > 1.5 * class_limit
--     200 > 90
-- INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
-- VALUES ('TEST_CAP_TOO_BIG', 'TEST_ROOM_CAP_BIG', 1, 300, 5, 1);
-- Expected: ERROR from enforce_capacity_ok(): room too big

-- 3) This should SUCCEED: 60 <= 80 <= 90
-- INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
-- VALUES ('TEST_CAP_OK', 'TEST_ROOM_CAP_OK', 1, 200, 5, 1);

-- Verify the successful insert
-- SELECT class_id, room_id, day_of_week, start_slot, length_slots, priority
-- FROM scheduled_meetings
-- WHERE class_id = 'TEST_CAP_OK';

-- Cleanup (optional)
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_CAP_%';
DELETE FROM classes            WHERE class_id LIKE 'TEST_CAP_%';
DELETE FROM rooms
 WHERE room_id IN (
   'TEST_ROOM_CAP_SMALL',
   'TEST_ROOM_CAP_OK',
   'TEST_ROOM_CAP_BIG'
 );

-- TEST CASE C4: No-room-time-overlap constraint
-- Expected:
--  - First INSERT: succeeds
--  - Second INSERT: ERROR (overlapping time in same room/day)
--  - Third INSERT: succeeds (non-overlapping time)

-- Cleanup any previous test data
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_OVERLAP_%';
DELETE FROM classes WHERE class_id LIKE 'TEST_OVERLAP_%';
DELETE FROM rooms WHERE room_id = 'TEST_ROOM_OVERLAP';

-- Create test room
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ROOM_OVERLAP', 100, 0, 0, false);

-- Create test classes (both valid for cap 100)
INSERT INTO classes (class_id, class_limit)
VALUES
  ('TEST_OVERLAP_1', 80),
  ('TEST_OVERLAP_2', 70);

-- First meeting: OK
INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
VALUES ('TEST_OVERLAP_1', 'TEST_ROOM_OVERLAP', 2, 50, 4, 1);
-- Occupies slots [50, 54)

-- Second meeting: overlaps same room/day -> should FAIL
INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
VALUES ('TEST_OVERLAP_2', 'TEST_ROOM_OVERLAP', 2, 52, 3, 1);
-- Expected: ERROR from no_room_time_overlap

-- Third meeting: non-overlapping -> should SUCCEED
INSERT INTO scheduled_meetings (class_id, room_id, day_of_week, start_slot, length_slots, priority)
VALUES ('TEST_OVERLAP_2', 'TEST_ROOM_OVERLAP', 2, 100, 3, 1);

-- Verify final scheduled meetings for this room
SELECT class_id, room_id, day_of_week, start_slot, length_slots
FROM scheduled_meetings
WHERE room_id = 'TEST_ROOM_OVERLAP'
ORDER BY day_of_week, start_slot;

-- Cleanup
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_OVERLAP_%';
DELETE FROM classes WHERE class_id LIKE 'TEST_OVERLAP_%';
DELETE FROM rooms WHERE room_id = 'TEST_ROOM_OVERLAP';

-- TEST CASE C5: schedule_class function basic usage
-- Expected:
--  - schedule_class inserts one row per '1' in days_mask
--  - scheduled_meetings contains entries for those days

SET search_path = timetable, public;

-- Cleanup any previous test data
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_SCHED_%';
DELETE FROM classes            WHERE class_id LIKE 'TEST_SCHED_%';
DELETE FROM rooms              WHERE room_id = 'TEST_ROOM_SCHED';

-- Create test room and class compatible with capacity rules
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ROOM_SCHED', 80, 0, 0, false);

INSERT INTO classes (class_id, class_limit)
VALUES ('TEST_SCHED_CLASS', 60);

-- Call schedule_class:
-- days_mask '0110000' => meets on day 1 and day 2 (Mon & Tue)
SELECT timetable.schedule_class(
  'TEST_SCHED_CLASS',   -- class
  'TEST_ROOM_SCHED',    -- room
  '0110000',            -- days_mask (Mon & Tue)
  40,                   -- start_slot
  3,                    -- length_slots
  1                     -- priority (student)
);

-- Verify that two meetings were created (for day_of_week 1 and 2)
SELECT class_id, room_id, day_of_week, start_slot, length_slots, priority
FROM scheduled_meetings
WHERE class_id = 'TEST_SCHED_CLASS'
ORDER BY day_of_week, start_slot;

-- Cleanup
DELETE FROM scheduled_meetings WHERE class_id LIKE 'TEST_SCHED_%';
DELETE FROM classes            WHERE class_id LIKE 'TEST_SCHED_%';
DELETE FROM rooms              WHERE room_id = 'TEST_ROOM_SCHED';

-- SECTION D: TRANSACTION TEST CASE (1) --

-- TEST CASE D1: Atomic Transaction Rollback
-- Ensures partial failures don't leave inconsistent data
-- Expected: No partial data remains after rollback

BEGIN;

INSERT INTO students (student_id) VALUES ('TEST_STUDENT_999');

INSERT INTO student_classes (student_id, class_id)
VALUES ('TEST_STUDENT_999', '1');

-- This will fail and abort the transaction
INSERT INTO student_classes (student_id, class_id)
VALUES ('TEST_STUDENT_999', 'INVALID_CLASS_999');

-- ROLLBACK;

-- Now this should return 0 rows
-- SELECT * FROM students WHERE student_id = 'TEST_STUDENT_999';

-- TEST CASE D2: Successful transaction across related tables
-- Expected:
--  - All inserts commit together (room, student, complaint)
--  - Data is visible after COMMIT

-- Cleanup any previous test data
DELETE FROM room_complaints WHERE room_id = 'TEST_ROOM_TX';
DELETE FROM scheduled_meetings WHERE room_id = 'TEST_ROOM_TX';
DELETE FROM students WHERE student_id = 'TEST_TX_STUDENT';
DELETE FROM rooms WHERE room_id = 'TEST_ROOM_TX';

BEGIN;

-- Create a test room
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ROOM_TX', 50, 0, 0, false);

-- Create a test student
INSERT INTO students (student_id)
VALUES ('TEST_TX_STUDENT');

-- Create a complaint linked to the new room and student
INSERT INTO room_complaints (
  room_id,
  reporter_student_id,
  priority,
  description,
  is_anonymous
) VALUES (
  'TEST_ROOM_TX',
  'TEST_TX_STUDENT',
  3,
  'Broken projector in test transaction room',
  false
);

COMMIT;

-- Verify all data committed
SELECT * FROM rooms WHERE room_id = 'TEST_ROOM_TX';
SELECT * FROM students WHERE student_id = 'TEST_TX_STUDENT';
SELECT room_id, reporter_student_id, status, description
FROM room_complaints
WHERE room_id = 'TEST_ROOM_TX' AND reporter_student_id = 'TEST_TX_STUDENT';
-- Expected: one room row, one student row, one complaint row

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_ROOM_TX';
DELETE FROM students WHERE student_id = 'TEST_TX_STUDENT';
DELETE FROM rooms WHERE room_id = 'TEST_ROOM_TX';

-- TEST CASE D3: Enrollment transaction respects class_limit
-- Expected:
--  - Only up to class_limit students are enrolled
--  - Final count of enrollments <= class_limit

-- Cleanup any previous test data
DELETE FROM student_classes WHERE class_id = 'TEST_TX_CLASS';
DELETE FROM students WHERE student_id LIKE 'TEST_TX_STU%';
DELETE FROM classes WHERE class_id = 'TEST_TX_CLASS';

-- Setup: class with limit 2 and three candidate students
INSERT INTO classes (class_id, class_limit)
VALUES ('TEST_TX_CLASS', 2);

INSERT INTO students (student_id)
VALUES
  ('TEST_TX_STU1'),
  ('TEST_TX_STU2'),
  ('TEST_TX_STU3');

BEGIN;

-- Enroll two students in a single transaction
INSERT INTO student_classes (student_id, class_id)
VALUES
  ('TEST_TX_STU1', 'TEST_TX_CLASS'),
  ('TEST_TX_STU2', 'TEST_TX_CLASS');

-- (Intentionally do not enroll a third student to avoid exceeding class_limit)
-- This models an application that enforces class_limit inside a single transaction.

COMMIT;

-- Verify that enrollments do not exceed class_limit
SELECT
  c.class_id,
  c.class_limit,
  COUNT(sc.student_id) AS enrolled_count
FROM classes c
LEFT JOIN student_classes sc ON sc.class_id = c.class_id
WHERE c.class_id = 'TEST_TX_CLASS'
GROUP BY c.class_id, c.class_limit;
-- Expected: enrolled_count = 2, class_limit = 2

-- Cleanup
DELETE FROM student_classes WHERE class_id = 'TEST_TX_CLASS';
DELETE FROM students WHERE student_id LIKE 'TEST_TX_STU%';
DELETE FROM classes WHERE class_id = 'TEST_TX_CLASS';


-- SECTION E: CONCURRENCY TEST CASE (1) --

-- TEST CASE E1: Serializable Isolation Level
-- Prevents concurrent update conflicts
-- Instructions: Run in TWO pgAdmin Query Tool windows simultaneously

-- WINDOW 1: Run this first
/*
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT capacity FROM rooms WHERE room_id = '1';
UPDATE rooms SET capacity = capacity - 5 WHERE room_id = '1';
-- PAUSE HERE - Do not commit yet
*/

-- WINDOW 2: While Window 1 is paused, run this
/*
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE rooms SET capacity = capacity + 10 WHERE room_id = '1';
-- This will BLOCK, waiting for Window 1
COMMIT;
*/

-- WINDOW 1: Now commit
/*
COMMIT;
-- Window 2 should now complete or error
*/

-- Expected: Serializable isolation prevents lost updates
-- One transaction succeeds, may get serialization error in the other

-- CLEANUP (run in both windows if needed):
/*
ROLLBACK;
*/

-- TEST CASE E2: Non-repeatable read under READ COMMITTED
-- Expected:
--  - Session 1 sees different capacity values in the same transaction
--  - Demonstrates a non-repeatable read

-- Setup (run once before starting the sessions)
DELETE FROM rooms WHERE room_id = 'TEST_ISO_ROOM';
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ISO_ROOM', 50, 0, 0, false);

-- SESSION 1 (Window 1)
-- Begin a transaction at READ COMMITTED
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- First read
SELECT room_id, capacity
FROM rooms
WHERE room_id = 'TEST_ISO_ROOM';
-- Expected: capacity = 50

-- SESSION 2 (Window 2)
-- In a separate session, run:
-- BEGIN;
-- UPDATE rooms
--   SET capacity = 80
--   WHERE room_id = 'TEST_ISO_ROOM';
-- COMMIT;

-- SESSION 1 (back to Window 1)
-- Second read in the same transaction
SELECT room_id, capacity
FROM rooms
WHERE room_id = 'TEST_ISO_ROOM';
-- Expected: capacity = 80 (value changed within the same transaction)

COMMIT;

-- Cleanup
DELETE FROM rooms WHERE room_id = 'TEST_ISO_ROOM';

-- TEST CASE E3: Non-repeatable read prevented under REPEATABLE READ
-- Expected:
--  - Session 1 sees the same capacity value on both reads
--  - UPDATE in Session 2 commits, but Session 1 keeps a stable snapshot

-- Setup (run once before starting the sessions)
DELETE FROM rooms WHERE room_id = 'TEST_ISO_ROOM';
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_ISO_ROOM', 50, 0, 0, false);

-- SESSION 1 (Window 1)
-- Begin a transaction at REPEATABLE READ
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- First read
SELECT room_id, capacity
FROM rooms
WHERE room_id = 'TEST_ISO_ROOM';
-- Expected: capacity = 50

-- SESSION 2 (Window 2)
-- In a separate session, run:
-- BEGIN;
-- UPDATE rooms
--   SET capacity = 80
--   WHERE room_id = 'TEST_ISO_ROOM';
-- COMMIT;

-- SESSION 1 (back to Window 1)
-- Second read in the same transaction
SELECT room_id, capacity
FROM rooms
WHERE room_id = 'TEST_ISO_ROOM';
-- Expected under REPEATABLE READ: still capacity = 50 (no non-repeatable read)

COMMIT;

-- Check final committed value after both sessions
SELECT room_id, capacity
FROM rooms
WHERE room_id = 'TEST_ISO_ROOM';
-- Expected: capacity = 80 (outside the transaction snapshot, latest committed value)

-- Cleanup
DELETE FROM rooms WHERE room_id = 'TEST_ISO_ROOM';


-- SECTION F: INDEXING PERFORMANCE TEST (1) --

-- TEST CASE F1: Index Performance Comparison
-- Demonstrates query optimization with indexing
-- Expected: Significant performance improvement with index
-- ========================================

-- Drop index if it exists
DROP INDEX IF EXISTS idx_classes_offering_test;

-- BEFORE INDEX: Running query without index...
EXPLAIN ANALYZE
SELECT c.class_id, c.offering_id, c.class_limit
FROM classes c
WHERE c.offering_id IN ('100', '200', '300', '400', '500')
ORDER BY c.offering_id, c.class_id;
-- Note: Look for "Seq Scan" and execution time

-- Creating index on offering_id...
CREATE INDEX idx_classes_offering_test ON classes(offering_id);

-- AFTER INDEX: Running same query with index...
EXPLAIN ANALYZE
SELECT c.class_id, c.offering_id, c.class_limit
FROM classes c
WHERE c.offering_id IN ('100', '200', '300', '400', '500')
ORDER BY c.offering_id, c.class_id;
-- Note: Look for "Index Scan" and faster execution time

-- Cleanup
DROP INDEX idx_classes_offering_test;

-- Expected:
-- - Without index: Sequential Scan, higher cost
-- - With index: Index Scan, lower cost, faster execution


-- SECTION G: Complaints subsystem tests

-- TEST CASE G1: Student-submitted complaint
-- Expected:
--  - Complaint inserted with reporter_student_id
--  - Query by room and status returns the complaint
-- =================================================

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM';
DELETE FROM students WHERE student_id = 'TEST_COMPLAINT_STUDENT';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM';

-- Setup room and student
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_COMPLAINT_ROOM', 40, 0, 0, false);

INSERT INTO students (student_id)
VALUES ('TEST_COMPLAINT_STUDENT');

-- Insert complaint as student
INSERT INTO room_complaints (
  room_id,
  reporter_student_id,
  priority,
  description,
  is_anonymous
) VALUES (
  'TEST_COMPLAINT_ROOM',
  'TEST_COMPLAINT_STUDENT',
  2,
  'Too noisy during exams',
  false
);

-- Query complaints by room and status
SELECT room_id, reporter_student_id, status, priority, description
FROM room_complaints
WHERE room_id = 'TEST_COMPLAINT_ROOM'
ORDER BY created_at DESC;
-- Expected: one complaint with reporter_student_id = TEST_COMPLAINT_STUDENT

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM';
DELETE FROM students WHERE student_id = 'TEST_COMPLAINT_STUDENT';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM';

-- TEST CASE G2: Instructor-submitted complaint
-- Expected:
--  - Complaint inserted with reporter_instructor_id
--  - Query by room and status returns the complaint

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM2';
DELETE FROM instructors WHERE instructor_id = 'TEST_COMPLAINT_INSTRUCTOR';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM2';

-- Setup room and instructor
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_COMPLAINT_ROOM2', 60, 0, 0, false);

INSERT INTO instructors (instructor_id)
VALUES ('TEST_COMPLAINT_INSTRUCTOR');

-- Insert complaint as instructor
INSERT INTO room_complaints (
  room_id,
  reporter_instructor_id,
  priority,
  description,
  is_anonymous
) VALUES (
  'TEST_COMPLAINT_ROOM2',
  'TEST_COMPLAINT_INSTRUCTOR',
  4,
  'Broken projector in lecture hall',
  false
);

-- Query complaints by room and status/priority
SELECT room_id, reporter_instructor_id, status, priority, description
FROM room_complaints
WHERE room_id = 'TEST_COMPLAINT_ROOM2'
ORDER BY priority DESC, created_at DESC;
-- Expected: one complaint with reporter_instructor_id = TEST_COMPLAINT_INSTRUCTOR

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM2';
DELETE FROM instructors WHERE instructor_id = 'TEST_COMPLAINT_INSTRUCTOR';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM2';

-- TEST CASE G3: CHECK constraint on reporter identity
-- Expected:
--  - Insert with BOTH reporter_student_id and reporter_instructor_id set causes ERROR

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM3';
DELETE FROM students WHERE student_id = 'TEST_COMPLAINT_STUDENT3';
DELETE FROM instructors WHERE instructor_id = 'TEST_COMPLAINT_INSTRUCTOR3';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM3';

-- Setup room, student, instructor
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_COMPLAINT_ROOM3', 30, 0, 0, false);

INSERT INTO students (student_id)
VALUES ('TEST_COMPLAINT_STUDENT3');

INSERT INTO instructors (instructor_id)
VALUES ('TEST_COMPLAINT_INSTRUCTOR3');

-- This should FAIL: both reporter_student_id and reporter_instructor_id set
INSERT INTO room_complaints (
  room_id,
  reporter_student_id,
  reporter_instructor_id,
  priority,
  description,
  is_anonymous
) VALUES (
  'TEST_COMPLAINT_ROOM3',
  'TEST_COMPLAINT_STUDENT3',
  'TEST_COMPLAINT_INSTRUCTOR3',
  3,
  'Invalid complaint with two reporters',
  false
);
-- Expected: ERROR from CHECK (num_nonnulls(...) = 1)

-- Cleanup (in case anything partially got through in earlier runs)
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM3';
DELETE FROM students WHERE student_id = 'TEST_COMPLAINT_STUDENT3';
DELETE FROM instructors WHERE instructor_id = 'TEST_COMPLAINT_INSTRUCTOR3';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM3';

-- TEST CASE G4: set_complaint_status updates status and resolved_at
-- Expected:
--  - Initial status = 'new', resolved_at IS NULL
--  - After calling set_complaint_status to 'resolved':
--      status = 'resolved', resolved_at IS NOT NULL, admin_notes updated

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS';

-- Setup room and a new complaint
INSERT INTO rooms (room_id, capacity, location_x, location_y, has_constraints)
VALUES ('TEST_COMPLAINT_ROOM_STATUS', 40, 0, 0, false);

INSERT INTO room_complaints (
  room_id,
  priority,
  description,
  is_anonymous
) VALUES (
  'TEST_COMPLAINT_ROOM_STATUS',
  5,
  'Heating not working',
  true
);

-- Check initial state
SELECT room_complaint_id, status, resolved_at, admin_notes
FROM room_complaints
WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS'
ORDER BY room_complaint_id DESC
LIMIT 1;
-- Expected: status = 'new', resolved_at IS NULL

-- Transition to resolved using helper function
SELECT set_complaint_status(
  rc.room_complaint_id,
  'resolved',
  'Issue fixed by maintenance'
)
FROM room_complaints rc
WHERE rc.room_id = 'TEST_COMPLAINT_ROOM_STATUS'
ORDER BY rc.room_complaint_id DESC
LIMIT 1;

-- Verify updated state
SELECT room_complaint_id, status, resolved_at, admin_notes
FROM room_complaints
WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS'
ORDER BY room_complaint_id DESC
LIMIT 1;
-- Expected: status = 'resolved', resolved_at IS NOT NULL,
--           admin_notes contains 'Issue fixed by maintenance'

-- Cleanup
DELETE FROM room_complaints WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS';
DELETE FROM rooms WHERE room_id = 'TEST_COMPLAINT_ROOM_STATUS';
