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


-- SECTION D: TRANSACTION TEST CASE (1) --

-- TEST CASE D1: Atomic Transaction Rollback
-- Ensures partial failures don't leave inconsistent data
-- Expected: No partial data remains after rollback

BEGIN;

-- Insert a test student
INSERT INTO students (student_id) VALUES ('TEST_STUDENT_999');

-- Insert valid enrollment
INSERT INTO student_classes (student_id, class_id)
VALUES ('TEST_STUDENT_999', '1');

-- Try to insert invalid enrollment (this will fail)
-- Class 'INVALID_999' does not exist
INSERT INTO student_classes (student_id, class_id)
VALUES ('TEST_STUDENT_999', 'INVALID_CLASS_999');

-- Rollback entire transaction
ROLLBACK;

-- Verify nothing was committed
SELECT * FROM students WHERE student_id = 'TEST_STUDENT_999';
-- Expected: 0 rows (rollback successful, no partial data)


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


-- SECTION F: INDEXING PERFORMANCE TEST (1) --

-- TEST CASE F1: Index Performance Comparison
-- Demonstrates query optimization with indexing
-- Expected: Significant performance improvement with index 

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
