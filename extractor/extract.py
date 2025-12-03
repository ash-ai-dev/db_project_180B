#!/usr/bin/env python3
"""
Extract UniTime-style university timetabling XML into CSVs.

Writes to ./out_csv:
  - rooms.csv
  - room_sharing_patterns.csv
  - room_sharing_departments.csv
  - classes.csv
  - class_instructors.csv
  - class_room_options.csv
  - class_time_options.csv
  - instructors.csv
  - constraints.csv
  - constraint_classes.csv
  - students.csv
  - student_offerings.csv
  - student_classes.csv
  - student_prohibited_classes.csv
"""

import csv
import os
import xml.etree.ElementTree as ET
from typing import Optional, Tuple

# Small helpers

def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)

def strip_ns(tag: str) -> str:
    if "}" in tag:
        return tag.split("}", 1)[1]
    return tag

def iter_children(elem, wanted_tag: str):
    for child in list(elem):
        if strip_ns(child.tag) == wanted_tag:
            yield child

def to_bool(text: Optional[str]) -> Optional[bool]:
    if text is None:
        return None
    t = text.strip().lower()
    if t in ("true", "t", "1", "yes", "y"):
        return True
    if t in ("false", "f", "0", "no", "n"):
        return False
    return None

def to_int(text: Optional[str]) -> Optional[int]:
    try:
        return int(text) if text is not None else None
    except ValueError:
        return None

def to_float(text: Optional[str]) -> Optional[float]:
    try:
        return float(text) if text is not None else None
    except ValueError:
        return None

def split_location(loc: Optional[str]) -> Tuple[Optional[int], Optional[int]]:
    if not loc or "," not in loc:
        return None, None
    x, y = loc.split(",", 1)
    return to_int(x), to_int(y)

class CsvWriter:
    def __init__(self, path: str, header: list[str]):
        self.f = open(path, "w", newline="", encoding="utf-8")
        self.w = csv.writer(self.f)
        self.w.writerow(header)
    def writerow(self, row):
        self.w.writerow(row)
    def close(self):
        self.f.close()

# Main extraction

def extract(xml_path: str, out_dir: str):
    ensure_dir(out_dir)

    rooms_w = CsvWriter(os.path.join(out_dir, "rooms.csv"),
                        ["room_id", "capacity", "location_x", "location_y", "has_constraints"])
    room_patterns_w = CsvWriter(os.path.join(out_dir, "room_sharing_patterns.csv"),
                                ["room_id", "unit_slots", "free_for_all_char", "not_available_char", "pattern_text"])
    room_depts_w = CsvWriter(os.path.join(out_dir, "room_sharing_departments.csv"),
                             ["room_id", "digit_char", "department_id"])

    classes_w = CsvWriter(os.path.join(out_dir, "classes.csv"),
                          ["class_id", "offering_id", "config_id", "subpart_id",
                           "committed", "class_limit", "scheduler", "dates_mask"])

    instructors_w = CsvWriter(os.path.join(out_dir, "instructors.csv"),
                              ["instructor_id"])

    class_instr_w = CsvWriter(os.path.join(out_dir, "class_instructors.csv"),
                              ["class_id", "instructor_id"])
    class_roomopt_w = CsvWriter(os.path.join(out_dir, "class_room_options.csv"),
                                ["class_id", "room_id", "pref"])
    class_timeopt_w = CsvWriter(os.path.join(out_dir, "class_time_options.csv"),
                                ["class_id", "days_mask", "start_slot", "length_slots", "pref"])

    constraints_w = CsvWriter(os.path.join(out_dir, "constraints.csv"),
                              ["pk", "external_id", "type", "pref_raw", "pref_numeric"])
    constr_classes_w = CsvWriter(os.path.join(out_dir, "constraint_classes.csv"),
                                 ["constraint_pk", "order_index", "class_id"])

    students_w = CsvWriter(os.path.join(out_dir, "students.csv"),
                           ["student_id"])
    stud_offerings_w = CsvWriter(os.path.join(out_dir, "student_offerings.csv"),
                                 ["student_id", "offering_id", "weight"])
    stud_classes_w = CsvWriter(os.path.join(out_dir, "student_classes.csv"),
                               ["student_id", "class_id"])
    stud_prohibited_w = CsvWriter(os.path.join(out_dir, "student_prohibited_classes.csv"),
                                  ["student_id", "class_id"])

    next_constraint_pk = 1
    seen_instructor_ids: set[str] = set()

    # Stream parse
    context = ET.iterparse(xml_path, events=("end",))
    for event, elem in context:
        tag = strip_ns(elem.tag)

        # ROOMS
        if tag == "room":
            # Only process top-level room definitions (they have 'capacity')
            if "capacity" not in elem.attrib:
                # This is a <room> inside <class> (i.e., a room option).
                # Do NOT clear it here; the <class> handler will read it.
                continue

            rid = elem.attrib.get("id")
            capacity = to_int(elem.attrib.get("capacity"))
            has_constr = to_bool(elem.attrib.get("constraint"))
            locx, locy = split_location(elem.attrib.get("location"))
            rooms_w.writerow([rid, capacity, locx, locy, has_constr])

            sharing = next(iter_children(elem, "sharing"), None)
            if sharing is not None:
                pattern_el = next(iter_children(sharing, "pattern"), None)
                unit_slots = to_int(pattern_el.attrib.get("unit")) if pattern_el is not None else None
                pattern_text = (pattern_el.text or "").strip() if pattern_el is not None else None

                ffa_el = next(iter_children(sharing, "freeForAll"), None)
                not_av_el = next(iter_children(sharing, "notAvailable"), None)
                free_for_all_char = ffa_el.attrib.get("value") if ffa_el is not None else None
                not_available_char = not_av_el.attrib.get("value") if not_av_el is not None else None
                room_patterns_w.writerow([rid, unit_slots, free_for_all_char, not_available_char, pattern_text])

                for dept in iter_children(sharing, "department"):
                    digit_char = dept.attrib.get("value")
                    dept_id = dept.attrib.get("id")
                    room_depts_w.writerow([rid, digit_char, dept_id])

            # safe to clear only real room definitions
            elem.clear()


        # CLASS DEFINITIONS (only real ones under <classes>)
        elif tag == "class":
            # Heuristic: only treat as a real "class definition" if it has class-def attributes
            is_definition = (
                ("classLimit" in elem.attrib) or
                ("offering" in elem.attrib) or
                (next(iter_children(elem, "time"), None) is not None)
            )
            if not is_definition:
                # This is a reference (likely under <students> or <constraint>)
                # DO NOT clear: parent (<student> / <constraint>) still needs it.
                continue

            cid = elem.attrib.get("id")
            offering = elem.attrib.get("offering")
            config = elem.attrib.get("config")
            subpart = elem.attrib.get("subpart")
            committed = to_bool(elem.attrib.get("committed"))
            class_limit = to_int(elem.attrib.get("classLimit"))
            scheduler = to_int(elem.attrib.get("scheduler"))
            dates_mask = elem.attrib.get("dates")
            classes_w.writerow([cid, offering, config, subpart, committed, class_limit, scheduler, dates_mask])

            for ins in iter_children(elem, "instructor"):
                instr_id = ins.attrib.get("id")
                if instr_id:
                    class_instr_w.writerow([cid, instr_id])
                    if instr_id not in seen_instructor_ids:
                        seen_instructor_ids.add(instr_id)

            for r in iter_children(elem, "room"):
                room_id = r.attrib.get("id")
                pref = to_float(r.attrib.get("pref"))
                class_roomopt_w.writerow([cid, room_id, pref])

            for t in iter_children(elem, "time"):
                days_mask = t.attrib.get("days")
                start_slot = to_int(t.attrib.get("start"))
                length_slots = to_int(t.attrib.get("length"))
                pref = to_float(t.attrib.get("pref"))
                class_timeopt_w.writerow([cid, days_mask, start_slot, length_slots, pref])

            # safe to clear only these full definitions
            elem.clear()

        # CONSTRAINTS + class membership
        elif tag == "constraint":
            external_id = elem.attrib.get("id")
            ctype = elem.attrib.get("type")
            pref_raw = elem.attrib.get("pref")
            try:
                pref_numeric = float(pref_raw)
            except (TypeError, ValueError):
                pref_numeric = None

            pk = next_constraint_pk
            next_constraint_pk += 1
            constraints_w.writerow([pk, external_id, ctype, pref_raw, pref_numeric])

            order_idx = 1
            for c in iter_children(elem, "class"):
                cid = c.attrib.get("id")
                if cid:
                    constr_classes_w.writerow([pk, order_idx, cid])
                    order_idx += 1

            elem.clear()

        # STUDENTS + links
        elif tag == "student":
            sid = elem.attrib.get("id")
            if sid:
                students_w.writerow([sid])

                for off in iter_children(elem, "offering"):
                    oid = off.attrib.get("id")
                    weight = to_float(off.attrib.get("weight"))
                    stud_offerings_w.writerow([sid, oid, weight])

                for c in iter_children(elem, "class"):
                    cid = c.attrib.get("id")
                    if cid:
                        stud_classes_w.writerow([sid, cid])

                for pc in iter_children(elem, "prohibited-class"):
                    cid = pc.attrib.get("id")
                    if cid:
                        stud_prohibited_w.writerow([sid, cid])

            elem.clear()

    for iid in sorted(seen_instructor_ids):
        instructors_w.writerow([iid])

    # Close writers
    for w in (rooms_w, room_patterns_w, room_depts_w,
              classes_w, class_instr_w, class_roomopt_w, class_timeopt_w,
              constraints_w, constr_classes_w,
              students_w, stud_offerings_w, stud_classes_w, stud_prohibited_w):
        w.close()

def main():
    # Always work under the current directory
    cwd = os.getcwd()

    # Input XML (change the file name below if yours is different, but I assume you downloaded it from where we did)
    xml_path = os.path.join(cwd, "pu-fal07-c8.xml")
    if not os.path.exists(xml_path):
        raise FileNotFoundError(f"XML not found at: {xml_path}")

    # Output directory (fixed name; no CLI params)
    out_dir = os.path.join(cwd, "out_csv")
    os.makedirs(out_dir, exist_ok=True)

    extract(xml_path, out_dir)
    print(f"CSVs written to: {out_dir}")

if __name__ == "__main__":
    main()