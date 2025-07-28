import sqlite3
import psycopg2
import getpass
import json
import os

USER = os.getenv("PI_USER")
PRINTER_NAME = os.getenv("PRINTER_NAME")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DP_PASSWORD = os.getenv("DB_PASSWORD")

# --- CONFIGURATION ---
sqlite_path = f"/home/{USER}/printer_data/database/moonraker-sql.db"
pg_config = {
    "host": DB_HOST,
    "port": DB_PORT,
    "dbname": DB_NAME,
    "user": DB_USER,
    "password": DP_PASSWORD
}
sqlite_conn = sqlite3.connect(sqlite_path)
sqlite_cursor = sqlite_conn.cursor()

pg_conn = psycopg2.connect(**pg_config)
pg_cursor = pg_conn.cursor()

pg_cursor.execute("SELECT print_start, print_end FROM print_jobs;")
existing_print_times = set(pg_cursor.fetchall())

# Query all relevant rows from SQLite
sqlite_cursor.execute("""
    SELECT filename, status, total_duration, start_time, end_time, metadata 
    FROM job_history 
    WHERE filename IS NOT NULL
""")

rows = sqlite_cursor.fetchall()

skipped = 0
uploaded = 0

for row in rows:
    filename, status, total_duration, start_time, end_time, metadata_blob = row
    
    if status =="in_progess":
        skipped += 1
        continue

    # Skip if print_start or print_end matches existing record
    if (start_time, end_time) in existing_print_times or (start_time,) in existing_print_times or (end_time,) in existing_print_times:
        skipped += 1
        continue

    # Parse metadata
    try:
        metadata_json = json.loads(metadata_blob.decode('utf-8'))
        filament_total = metadata_json.get('filament_total')
        filament_type = metadata_json.get('filament_type')
        filament_weight = metadata_json.get('filament_weight_total')
    except Exception as e:
        print(f"Skipping entry due to metadata parse error: {e}")
        continue

    # Insert into Postgres
    pg_cursor.execute(f"""
        INSERT INTO {DB_NAME} (
            filename, status, total_duration, filament_total,
            filament_type, filament_weight, print_start, print_end, printer_name
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """, (
        filename, status, total_duration, filament_total,
        filament_type, filament_weight, start_time, end_time, PRINTER_NAME
    ))
    
    uploaded += 1

# Commit and close
pg_conn.commit()
pg_cursor.close()
pg_conn.close()
sqlite_conn.close()
print(f"Skipped {skipped} duplicates.")
print(f"Uploaded {uploaded} new entries.")
print("Upload complete.")
