# Let’s Table This: Smart Campus Resource Management

A PostgreSQL based scheduling and room management system for SJSU that ingests UniTime style timetable data, enforces room and time constraints, and provides a structured way to track complaints about rooms and facilities.

This project was created for CMPE 180B to explore real world database design, data pipelines, scheduling logic, and concurrency control.

---

## Team

Fill in your actual group members here.

- Name 1  -  Role 1  -  email1@sjsu.edu  
- Name 2  -  Role 2  -  email2@sjsu.edu  
- Name 3  -  Role 3  -  email3@sjsu.edu  
- Name 4  -  Role 4  -  email4@sjsu.edu  


## Project Overview

At the start of each semester, classrooms are often double booked, too small for the number of enrolled students, or simply hard for student groups to reserve. There is no simple self service way for students and faculty to see what rooms are actually free, at what times, and under which constraints.

This project builds a dedicated schema and supporting logic that:

1. Loads official timetable data from a UniTime style XML export.  
2. Cleans and normalizes the data into a PostgreSQL schema.  
3. Enforces time and room capacity rules at the database level.  
4. Provides helper functions for scheduling class meetings and user bookings.  
5. Supports a complaint system so users can report room issues and track their status.  
6. Wraps scheduling operations in a safe concurrency layer so multiple users cannot corrupt the schedule.

---

## Key Features

- **Normalized timetable schema** for rooms, classes, meetings, and complaints.  
- **Data pipeline** from XML to CSV to staging tables to final tables.  
- **Automatic overlap prevention** using a GiST exclusion constraint on time ranges.  
- **Room capacity checks** enforced via trigger functions on `scheduled_meetings`.  
- **Priority system** so higher priority users can override lower priority bookings in a controlled way.  
- **Complaint tracking** with helper procedures for adding and updating complaint status.  
- **Concurrency wrapper** that uses serializable transactions and retry logic to handle conflicts.

---

## Data Sources

- Input format: UniTime style timetabling XML file (university scheduling export).  
- The XML is broken into multiple CSV files, one per logical table, for example:

  - `rooms.csv`  
  - `classes.csv`  
  - `meetings.csv`  
  - `instructors.csv`  
  - `students.csv`

- The CSV files are then loaded into staging tables and finally deduplicated into the main `timetable` schema.

---

## Tech Stack

- **Database**: PostgreSQL  
- **Scripting**: Python (for XML parsing and CSV generation)  
- **Environment**: Jupyter Notebook for running and documenting the full pipeline script  
- **PostgreSQL Features Used**:
  - Schemas
  - Foreign keys with cascading behavior
  - GiST indexes and exclusion constraints
  - Triggers and stored procedures
  - Serializable isolation level and retry logic

---

## Schema Overview

The core schema is named `timetable`. It is designed to encode the scheduling domain cleanly and prevent inconsistent data.

Key tables include:

- `rooms`  
  - Stores room metadata such as `room_id`, `capacity`, and layout information.  
  - Example columns:  
    - `room_id` (primary key, text)  
    - `capacity` (integer)  
    - `location_x`, `location_y` or similar coordinates  
    - `has_constraints` (boolean flag for special rules)

- `classes`  
  - Stores information about course offerings.  
  - Example columns:  
    - `class_id` (primary key)  
    - `course_id`, `section`, `title`  
    - `expected_enrollment`  

- `scheduled_meetings`  
  - Central table that ties classes to rooms at specific times.  
  - Typical columns:
    - `meeting_id` (primary key)  
    - `class_id` (foreign key references `classes`)  
    - `room_id` (foreign key references `rooms`)  
    - `day_of_week`  
    - `start_time`, `end_time` (time or timestamptz)  
    - `priority` (integer or enum to capture who scheduled it)  

  - Constraints:
    - Foreign key to `classes` with `ON DELETE CASCADE` so deleting a class removes its meetings.  
    - Foreign key to `rooms` with delete restricted so rooms cannot be removed while they have meetings.  
    - A GiST exclusion constraint on the room and time interval to prevent overlapping bookings for the same room.

- `room_complaints`  
  - Stores complaints or notes about rooms.  
  - Typical columns:
    - `complaint_id` (primary key)  
    - `room_id` (foreign key references `rooms`)  
    - `submitted_by` (optional, can be null for anonymous complaints)  
    - `description`  
    - `status` (for example `open`, `in_progress`, `resolved`, `dismissed`)  
    - `created_at`, `updated_at`, `resolved_at`  

---

## Data Pipeline

The data pipeline is responsible for taking a UniTime XML export and turning it into a fully populated PostgreSQL schema.

High level stages:

1. **XML to CSV (Python script)**  
   - A Python script parses the UniTime XML.  
   - Each logical entity is extracted into a separate CSV file.  
   - Helper functions handle:
     - Splitting long XML structures into flat rows.  
     - Cleaning and normalizing values (trimming strings, mapping codes, etc).  

2. **CSV to staging tables (`*_stg`)**  
   - Within PostgreSQL, temporary staging tables are created for each CSV.  
   - These tables match the CSV structure as closely as possible.  
   - Data is loaded using the `COPY` command:
     ```sql
     COPY timetable.rooms_stg FROM '/path/to/rooms.csv' CSV HEADER;
     ```
   - This allows fast, repeatable loading without immediately triggering constraint errors in the main tables.

3. **Staging to final tables with deduplication**  
   - A helper function, for example `timetable.load_csv_dedup(target_table, csv_path)`, is responsible for:
     - Creating the staging table.  
     - Running `COPY` to load the CSV into the staging table.  
     - Inserting from staging into the target table while skipping duplicates or conflicting rows.  
     - Dropping the staging table once finished.

4. **Dynamic load ordering**  
   - Tables are loaded in an order that respects foreign key dependencies, for example:
     1. `rooms`  
     2. `classes`  
     3. `scheduled_meetings`  
     4. `room_complaints` (if it depends on `rooms`)  
   - A base path such as `timetable.base_path` is used so all CSVs can be referenced consistently.

5. **Verification queries**  
   - After loading, the script runs queries that count the rows in each table and report them.  
   - This helps detect obvious pipeline issues like a critical table having zero rows.

---

## Scheduling Logic

The scheduling behavior is encoded directly into the database so that rules are always enforced, regardless of which client calls it.

### Overlap Prevention

- The `scheduled_meetings` table uses a GiST based exclusion constraint to ensure that two meetings in the same room cannot overlap in time.  
- Conceptually:

  ```sql
  ALTER TABLE timetable.scheduled_meetings
  ADD CONSTRAINT no_room_overlap
  EXCLUDE USING gist (
      room_id WITH =,
      tstzrange(start_time, end_time) WITH &&
  );
  ```

* Any `INSERT` or `UPDATE` that would violate this rule is automatically rejected by PostgreSQL.

### Capacity Rules

* A trigger function runs before insert or update on `scheduled_meetings`.
* The trigger:

  * Looks up the `capacity` of the target room.
  * Looks up the `expected_enrollment` or limit of the class.
  * Rejects the transaction if:

    * The class size is greater than the room capacity.
    * Or the room is excessively large compared to the class size if you enforce that rule.

This means that bad schedules are blocked at the data layer and cannot silently sneak into the system.

### Priority System

* Each meeting or scheduling request carries a numeric `priority`.
* Higher priority users (for example, academic departments) can be allowed to override lower priority bookings.
* This can be implemented with:

  * A stored procedure that checks existing meetings in the same time slot.
  * Logic that either:

    * Rejects the new booking, or
    * Deletes or updates the lower priority booking before inserting the new one.

---

## Complaint System

To capture real world issues with rooms, the project includes a complaint tracking subsystem.

### Tables and Procedures

* `room_complaints` table described above.

* Helper procedures:

  1. `add_room_complaint(room_id, submitted_by, description, is_anonymous)`

     * Inserts a new complaint.
     * Handles anonymity by either storing the submitter or keeping it null.
     * Initializes status to `open` and timestamps `created_at`.

  2. `set_complaint_status(complaint_id, new_status)`

     * Updates the status of an existing complaint to `in_progress`, `resolved`, or `dismissed`.
     * Automatically sets `resolved_at` when status becomes `resolved`.
     * Updates `updated_at` on every status change.

This design lets staff triage and close complaints directly in the database while keeping an audit trail.

---

## Concurrency and Transactions

Real users may attempt to schedule or modify meetings at the same time. To avoid race conditions, the project adds a concurrency wrapper around the main scheduling function.

Typical pattern:

1. Wrap scheduling logic inside a serializable transaction:

   ```sql
   SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
   ```

2. Attempt to perform the scheduling action (for example, calling `schedule_class`).

3. If PostgreSQL raises a serialization failure due to a conflicting concurrent transaction, catch the error and retry.

4. Limit the number of retries (for example, up to 5 attempts).

5. If all retries fail, return an error to the caller rather than leaving the database in a bad state.

This pattern allows many users to attempt scheduling concurrently while still preserving a consistent timetable.

---

## Running the Project

Below is a typical flow to get the system running from scratch.

1. **Create the database**

   ```bash
   createdb smart_campus
   ```

2. **Run the schema and pipeline script**

   * Open the Jupyter notebook `Smart_Campus_Resource_Management.ipynb`.
   * Step through the cells in order:

     * Create and drop the `timetable` schema.
     * Define tables, triggers, and constraints.
     * Run the loader functions to populate tables from CSVs.

3. **Place the CSV and XML files**

   * Put the UniTime XML file in a known folder, for example `./data/raw/`.
   * Configure the Python extraction script to output CSVs into `./data/csv/`.
   * Update `timetable.base_path` or equivalent variables to point to the CSV directory.

4. **Verify data**

   * Run the final verification queries in the notebook to check row counts.
   * Inspect a few sample rows in each table to ensure values look correct.

5. **Try scheduling operations**

   * Call the `schedule_class` style helper function for some test classes.
   * Verify that overlapping or over capacity requests are rejected.
   * Add and update complaints using the provided procedures and confirm status changes.

---

## Testing

Ideas for testing the system:

* **Unit style tests using SQL scripts**:

  * Insert rooms and classes with specific capacities.
  * Attempt to schedule overlapping meetings and confirm that the insert fails.
  * Attempt to schedule an oversized class in a small room and confirm that the trigger blocks it.

* **Concurrency tests**:

  * Open multiple sessions and attempt to schedule the same room and time with different priorities.
  * Confirm that the higher priority booking wins and the database remains consistent.

* **Complaint workflow tests**:

  * Insert new complaints, update statuses through all possible values, and verify timestamps.

---

## Future Work

Some possible extensions:

* Web UI for browsing free rooms and submitting complaints.
* Integration with SJSU authentication and real user roles.
* More detailed constraint modeling for special rooms, equipment needs, and accessibility.
* Automatic suggestion of alternative rooms when a request conflicts.
* Analytics on room usage and complaint frequency to guide facility improvements.
