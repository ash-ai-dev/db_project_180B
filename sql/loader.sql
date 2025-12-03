-- Make sure we use the timetable schema by default
SET search_path = timetable, public;

-- 1. Define the reusable CSV loader procedure
CREATE OR REPLACE PROCEDURE timetable.load_csv_dedup(
  target_table regclass,
  csv_path     text,
  col_list     text,
  pk_cols      text
)
LANGUAGE plpgsql
AS $$
DECLARE
  -- Use the unqualified table name + '_stg' as the temp table name
  stg_name text := quote_ident(split_part(target_table::text, '.', 2) || '_stg');
  tgt_name text := target_table::text;
  sql      text;
BEGIN
  -- Drop any previous staging table for this target
  EXECUTE format('DROP TABLE IF EXISTS %s', stg_name);

  -- Create a temp staging table with the same structure as the target
  EXECUTE format(
    'CREATE TEMP TABLE %s (LIKE %s INCLUDING DEFAULTS)',
    stg_name,
    tgt_name
  );

  -- Bulk load CSV into the staging table
  sql := format(
    $f$COPY %s (%s) FROM %L CSV HEADER$f$,
    stg_name,
    col_list,
    csv_path
  );
  EXECUTE sql;

  -- Deduplicate by pk_cols and insert into the real table
  sql := format(
    $f$
      INSERT INTO %s (%s)
      SELECT DISTINCT ON (%s) %s
      FROM %s
      ORDER BY %s
      ON CONFLICT DO NOTHING
    $f$,
    tgt_name,   -- INSERT INTO target
    col_list,   -- all columns
    pk_cols,    -- DISTINCT ON pk
    col_list,   -- select the same columns
    stg_name,   -- from staging
    pk_cols     -- ORDER BY pk
  );
  EXECUTE sql;

  -- Drop staging table
  EXECUTE format('DROP TABLE %s', stg_name);
END;
$$;

-- 2. Point base_path at your CSV directory
SET timetable.base_path = '/Users/shervan/Desktop/smart-campus/out_csv';

-- 3. Load each table from its CSV

CALL timetable.load_csv_dedup(
  'timetable.rooms',
  current_setting('timetable.base_path') || '/rooms.csv',
  'room_id,capacity,location_x,location_y,has_constraints',
  'room_id'
);

CALL timetable.load_csv_dedup(
  'timetable.room_sharing_patterns',
  current_setting('timetable.base_path') || '/room_sharing_patterns.csv',
  'room_id,unit_slots,free_for_all_char,not_available_char,pattern_text',
  'room_id'
);

CALL timetable.load_csv_dedup(
  'timetable.room_sharing_departments',
  current_setting('timetable.base_path') || '/room_sharing_departments.csv',
  'room_id,digit_char,department_id',
  'room_id,digit_char,department_id'
);

CALL timetable.load_csv_dedup(
  'timetable.classes',
  current_setting('timetable.base_path') || '/classes.csv',
  'class_id,offering_id,config_id,subpart_id,committed,class_limit,scheduler,dates_mask',
  'class_id'
);

CALL timetable.load_csv_dedup(
  'timetable.class_instructors',
  current_setting('timetable.base_path') || '/class_instructors.csv',
  'class_id,instructor_id',
  'class_id,instructor_id'
);

CALL timetable.load_csv_dedup(
  'timetable.class_room_options',
  current_setting('timetable.base_path') || '/class_room_options.csv',
  'class_id,room_id,pref',
  'class_id,room_id'
);

CALL timetable.load_csv_dedup(
  'timetable.class_time_options',
  current_setting('timetable.base_path') || '/class_time_options.csv',
  'class_id,days_mask,start_slot,length_slots,pref',
  'class_id,days_mask,start_slot,length_slots'
);

CALL timetable.load_csv_dedup(
  'timetable.instructors',
  current_setting('timetable.base_path') || '/instructors.csv',
  'instructor_id',
  'instructor_id'
);

CALL timetable.load_csv_dedup(
  'timetable.constraints',
  current_setting('timetable.base_path') || '/constraints.csv',
  'pk,external_id,type,pref_raw,pref_numeric',
  'pk'
);

CALL timetable.load_csv_dedup(
  'timetable.constraint_classes',
  current_setting('timetable.base_path') || '/constraint_classes.csv',
  'constraint_pk,order_index,class_id',
  'constraint_pk,order_index'
);

CALL timetable.load_csv_dedup(
  'timetable.students',
  current_setting('timetable.base_path') || '/students.csv',
  'student_id',
  'student_id'
);

CALL timetable.load_csv_dedup(
  'timetable.student_offerings',
  current_setting('timetable.base_path') || '/student_offerings.csv',
  'student_id,offering_id,weight',
  'student_id,offering_id'
);

CALL timetable.load_csv_dedup(
  'timetable.student_classes',
  current_setting('timetable.base_path') || '/student_classes.csv',
  'student_id,class_id',
  'student_id,class_id'
);

CALL timetable.load_csv_dedup(
  'timetable.student_prohibited_classes',
  current_setting('timetable.base_path') || '/student_prohibited_classes.csv',
  'student_id,class_id',
  'student_id,class_id'
);

-- 4. Quick sanity check counts
SELECT 'rooms' AS t, COUNT(*) FROM timetable.rooms
UNION ALL SELECT 'room_sharing_patterns', COUNT(*) FROM timetable.room_sharing_patterns
UNION ALL SELECT 'room_sharing_departments', COUNT(*) FROM timetable.room_sharing_departments
UNION ALL SELECT 'classes', COUNT(*) FROM timetable.classes
UNION ALL SELECT 'class_instructors', COUNT(*) FROM timetable.class_instructors
UNION ALL SELECT 'class_room_options', COUNT(*) FROM timetable.class_room_options
UNION ALL SELECT 'class_time_options', COUNT(*) FROM timetable.class_time_options
UNION ALL SELECT 'instructors', COUNT(*) FROM timetable.instructors
UNION ALL SELECT 'constraints', COUNT(*) FROM timetable.constraints
UNION ALL SELECT 'constraint_classes', COUNT(*) FROM timetable.constraint_classes
UNION ALL SELECT 'students', COUNT(*) FROM timetable.students
UNION ALL SELECT 'student_offerings', COUNT(*) FROM timetable.student_offerings
UNION ALL SELECT 'student_classes', COUNT(*) FROM timetable.student_classes
UNION ALL SELECT 'student_prohibited_classes', COUNT(*) FROM timetable.student_prohibited_classes;
