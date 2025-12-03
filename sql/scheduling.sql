CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE scheduled_meetings (
  class_id VARCHAR(50) NOT NULL REFERENCES classes(class_id) ON DELETE CASCADE,
  room_id  VARCHAR(50) NOT NULL REFERENCES rooms(room_id) ON DELETE RESTRICT,
  day_of_week  SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sun to 6=Sat
  start_slot INTEGER NOT NULL CHECK (start_slot >= 0),
  length_slots INTEGER NOT NULL CHECK (length_slots > 0),
  slot_range int4range GENERATED ALWAYS AS (int4range(start_slot, start_slot + length_slots, '[)')) STORED,

  PRIMARY KEY (class_id, day_of_week, start_slot)
);

-- No two meetings should overlap in the same room on the same day
ALTER TABLE scheduled_meetings
ADD CONSTRAINT no_room_time_overlap
EXCLUDE USING gist (
  room_id WITH =,
  day_of_week WITH =,
  slot_range WITH &&
);

-- Priority: 1 = student, 2 = instructor, 3 = administrator
ALTER TABLE scheduled_meetings
  ADD COLUMN IF NOT EXISTS priority SMALLINT NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 3);

-- Keep overlap rule consistent (no priority in the constraint)
ALTER TABLE scheduled_meetings DROP CONSTRAINT IF EXISTS no_room_time_overlap;

ALTER TABLE scheduled_meetings
ADD CONSTRAINT no_room_time_overlap
EXCLUDE USING gist (
  room_id     WITH =,
  day_of_week WITH =,
  slot_range  WITH &&
);


-- Make sure we are talking about the right schema
CREATE SCHEMA IF NOT EXISTS timetable;
SET search_path = timetable;

-- Recreate the function with fully-qualified table names
CREATE OR REPLACE FUNCTION timetable.enforce_capacity_ok()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  room_cap   integer;
  class_lim  integer;
BEGIN
  -- Look up capacity from timetable.rooms
  SELECT r.capacity
    INTO room_cap
  FROM timetable.rooms r
  WHERE r.room_id = NEW.room_id;

  IF room_cap IS NULL THEN
    RAISE EXCEPTION 'Room % not found in timetable.rooms', NEW.room_id;
  END IF;

  -- Look up class_limit from timetable.classes
  SELECT c.class_limit
    INTO class_lim
  FROM timetable.classes c
  WHERE c.class_id = NEW.class_id;

  IF class_lim IS NULL THEN
    RAISE EXCEPTION 'Class % not found in timetable.classes', NEW.class_id;
  END IF;

  -- Lower bound: room must fit class
  IF room_cap < class_lim THEN
    RAISE EXCEPTION 'Capacity violation: room % cap % < class % limit %',
      NEW.room_id, room_cap, NEW.class_id, class_lim;
  END IF;

  -- Upper bound to avoid huge waste
  IF room_cap > class_lim * 1.5 THEN
    RAISE EXCEPTION 'Room % is too large for class % (cap %, limit %)',
      NEW.room_id, NEW.class_id, room_cap, class_lim;
  END IF;

  RETURN NEW;
END;
$$;

-- Reattach trigger to scheduled_meetings
DROP TRIGGER IF EXISTS trg_capacity_ok ON timetable.scheduled_meetings;

CREATE TRIGGER trg_capacity_ok
BEFORE INSERT OR UPDATE OF room_id, class_id
ON timetable.scheduled_meetings
FOR EACH ROW
EXECUTE FUNCTION timetable.enforce_capacity_ok();



-- Usage:
-- Student booking (default priority=1)
-- SELECT schedule_class('STUDY-GRP-1', 'ENG-241', '0111100', 90, 6);
-- Instructor booking (preempts students if overlapping)
-- SELECT schedule_class('CS101-LEC', 'ENG-241', '0111100', 90, 6, 2);
-- Admin booking (preempts students & instructors if overlapping)
-- SELECT schedule_class('ADMIN-ALLOC', 'ENG-241', '0111100', 90, 6, 3);


SET search_path = timetable, public;

CREATE OR REPLACE FUNCTION timetable.schedule_class(
  p_class_id   text,
  p_room_id    text,
  p_days_mask  text,     -- '0111100' (Mon..Sun)
  p_start_slot integer,
  p_length     integer,
  p_priority   integer DEFAULT 1  -- 1=student, 2=instructor, 3=admin
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  d        smallint;
  v_range  int4range := int4range(p_start_slot, p_start_slot + p_length, '[)');
BEGIN
  FOR d IN 0..6 LOOP
    IF substr(p_days_mask, d + 1, 1) = '1' THEN
      -- Remove lower-priority overlaps in the same room/day/time
      DELETE FROM scheduled_meetings
       WHERE room_id = p_room_id
         AND day_of_week = d
         AND slot_range && v_range
         AND priority < p_priority;

      -- Insert one meeting for this day; capacity + overlap constraints will run
      INSERT INTO scheduled_meetings (
        class_id, room_id, day_of_week, start_slot, length_slots, priority
      )
      VALUES (
        p_class_id, p_room_id, d, p_start_slot, p_length, p_priority
      );
    END IF;
  END LOOP;
END;
$$;
