SET search_path = timetable, public;

-- Drop and recreate the enum type and table so the file is self contained
DROP TYPE IF EXISTS complaint_status CASCADE;
CREATE TYPE complaint_status AS ENUM ('new','open','in_progress','resolved','dismissed');

DROP TABLE IF EXISTS room_complaints CASCADE;

CREATE TABLE room_complaints (
  room_complaint_id BIGSERIAL PRIMARY KEY,

  room_id      VARCHAR(50) NOT NULL
               REFERENCES rooms(room_id) ON DELETE CASCADE,

  -- Exactly one of these must be non null
  reporter_student_id    VARCHAR(50)
               REFERENCES students(student_id) ON DELETE SET NULL,
  reporter_instructor_id VARCHAR(50)
               REFERENCES instructors(instructor_id) ON DELETE SET NULL,

  is_anonymous  BOOLEAN NOT NULL DEFAULT FALSE,
  title         VARCHAR(120) NOT NULL DEFAULT 'General room complaint',
  description   TEXT NOT NULL,

  -- 1 = high, 2 = normal, 3 = low
  priority      SMALLINT NOT NULL DEFAULT 2,

  status        complaint_status NOT NULL DEFAULT 'new',

  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at   TIMESTAMPTZ,
  admin_notes   TEXT,

  CHECK (num_nonnulls(reporter_student_id, reporter_instructor_id) = 1),
  CHECK (priority BETWEEN 1 AND 5)
);

-- Trigger to keep updated_at in sync
CREATE OR REPLACE FUNCTION touch_room_complaints_updated_at()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_room_complaints ON room_complaints;

CREATE TRIGGER trg_touch_room_complaints
BEFORE UPDATE ON room_complaints
FOR EACH ROW
EXECUTE FUNCTION touch_room_complaints_updated_at();

-- Useful indexes
CREATE INDEX IF NOT EXISTS idx_room_complaints_room_status
  ON room_complaints (room_id, status);

CREATE INDEX IF NOT EXISTS idx_room_complaints_status_priority_created
  ON room_complaints (status, priority, created_at DESC);

-- Function to add a complaint
CREATE OR REPLACE FUNCTION add_room_complaint(
  p_room_id        VARCHAR,
  p_title          VARCHAR,
  p_description    TEXT,
  p_priority       INTEGER DEFAULT 2,
  p_student_id     VARCHAR DEFAULT NULL,
  p_instructor_id  VARCHAR DEFAULT NULL,
  p_anonymous      BOOLEAN DEFAULT FALSE
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
BEGIN
  -- Exactly one of student or instructor must be provided
  IF (p_student_id IS NULL) = (p_instructor_id IS NULL) THEN
    RAISE EXCEPTION
      'Exactly one of p_student_id or p_instructor_id must be non null';
  END IF;

  IF p_priority NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION
      'p_priority must be between 1 and 3 (1=high, 2=normal, 3=low). Got %',
      p_priority;
  END IF;

  INSERT INTO room_complaints (
    room_id,
    title,
    description,
    priority,
    reporter_student_id,
    reporter_instructor_id,
    is_anonymous
  )
  VALUES (
    p_room_id,
    p_title,
    p_description,
    p_priority,
    p_student_id,
    p_instructor_id,
    p_anonymous
  )
  RETURNING room_complaint_id INTO v_id;

  RETURN v_id;
END;
$$;

-- Function to update complaint status and notes
CREATE OR REPLACE FUNCTION set_complaint_status(
  p_complaint_id BIGINT,
  p_status       complaint_status,
  p_admin_notes  TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE room_complaints
     SET status      = p_status,
         resolved_at = CASE
                         WHEN p_status IN ('resolved','dismissed')
                           THEN now()
                         ELSE NULL
                       END,
         admin_notes = p_admin_notes
   WHERE room_complaint_id = p_complaint_id;
END;
$$;

-- Seed some basic data if needed
INSERT INTO rooms (room_id) VALUES
  ('ENG-241'),
  ('SCI-102')
ON CONFLICT (room_id) DO NOTHING;

INSERT INTO students (student_id) VALUES
  ('s123456')
ON CONFLICT (student_id) DO NOTHING;

INSERT INTO instructors (instructor_id) VALUES
  ('i7890')
ON CONFLICT (instructor_id) DO NOTHING;

-- Example usage

-- Student files a complaint
SELECT add_room_complaint(
  p_room_id        => 'ENG-241',
  p_title          => 'Projector not turning on',
  p_description    => 'Tried multiple HDMI cables; fan spins up, no image.',
  p_priority       => 1,
  p_student_id     => 's123456',
  p_instructor_id  => NULL,
  p_anonymous      => FALSE
);

-- Instructor files a complaint anonymous
SELECT add_room_complaint(
  p_room_id        => 'SCI-102',
  p_title          => 'Broken chair at back row',
  p_description    => 'Third from left, back row.',
  p_priority       => 2,
  p_student_id     => NULL,
  p_instructor_id  => 'i7890',
  p_anonymous      => TRUE
);

-- Mark complaint id 42 as resolved with notes
SELECT set_complaint_status(
  p_complaint_id   => 42,
  p_status         => 'resolved',
  p_admin_notes    => 'Replaced projector lamp on 2025-11-22'
);
