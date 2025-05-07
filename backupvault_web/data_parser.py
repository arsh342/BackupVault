# backupvault_web/data_parser.py
import os
import csv
from datetime import datetime, timedelta, timezone # Ensure timezone is imported
import shutil 

USER_HOME = os.path.expanduser("~")
APP_DIR_BASE = os.path.join(USER_HOME, ".backupvault")
BACKUP_CONFIG_FILE = os.path.join(APP_DIR_BASE, "backupvault.conf")
BACKUP_RUNS_LOG_FILE = os.path.join(APP_DIR_BASE, "logs", "backup_runs.csv")
DETAILED_LOGS_DIR = os.path.join(APP_DIR_BASE, "logs", "details")

def get_backup_config():
    config = {}
    if not os.path.exists(BACKUP_CONFIG_FILE):
        print(f"Warning: Config file not found at {BACKUP_CONFIG_FILE}")
        return None
    try:
        with open(BACKUP_CONFIG_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value_with_quotes = line.split("=", 1)
                    value = value_with_quotes.strip()
                    if (value.startswith('"') and value.endswith('"')) or \
                       (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1]
                    config[key.strip()] = value
    except Exception as e:
        print(f"Error reading config file {BACKUP_CONFIG_FILE}: {e}")
        return None
    return config

def get_backup_history():
    history = []
    if not os.path.exists(BACKUP_RUNS_LOG_FILE):
        print(f"Warning: Backup runs log not found at {BACKUP_RUNS_LOG_FILE}")
        return history
    try:
        with open(BACKUP_RUNS_LOG_FILE, 'r', newline='', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                try:
                    row['backup_size_bytes'] = int(row.get('backup_size_bytes', 0))
                    row['start_time'] = datetime.fromisoformat(row['start_time']) if row.get('start_time') else None
                    row['end_time'] = datetime.fromisoformat(row['end_time']) if row.get('end_time') else None
                    history.append(row)
                except (ValueError, TypeError) as e:
                    print(f"Skipping malformed row in {BACKUP_RUNS_LOG_FILE}: {row} - Error: {e}")
    except Exception as e:
        print(f"Error reading or parsing backup runs log {BACKUP_RUNS_LOG_FILE}: {e}")
    # Sort, ensuring timezone aware comparison if using datetime.min as placeholder for None start_times
    history.sort(key=lambda x: x.get('start_time') or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    return history

def get_detailed_log_content(log_file_name):
    if not log_file_name or ".." in log_file_name or "/" in log_file_name or "\\" in log_file_name:
        print(f"Warning: Invalid log file name requested: {log_file_name}")
        return "Error: Invalid log file name."
    full_log_path = os.path.join(DETAILED_LOGS_DIR, log_file_name)
    if not os.path.exists(full_log_path):
        print(f"Warning: Detailed log file not found: {full_log_path}")
        return f"Error: Log file '{log_file_name}' not found."
    try:
        with open(full_log_path, 'r', encoding='utf-8') as f: return f.read()
    except Exception as e:
        print(f"Error reading detailed log file {full_log_path}: {e}")
        return f"Error reading log file '{log_file_name}': {e}"

def calculate_next_run_time(last_run_time_iso, frequency, custom_schedule_str=""):
    if not frequency: return "N/A (Frequency not configured)"
    now = datetime.now().astimezone() # Key fix: make 'now' timezone-aware (local)
    last_run = None
    if last_run_time_iso:
        try: last_run = datetime.fromisoformat(last_run_time_iso)
        except ValueError: pass
    
    calc_base_time = last_run if last_run and last_run < now else now
    next_run_candidate = None
    run_minute, run_hour = 0, 2 
    try:
        if custom_schedule_str and len(custom_schedule_str.split()) >= 2:
            parts = custom_schedule_str.split()
            if parts[0].isdigit(): run_minute = int(parts[0])
            if parts[1].isdigit(): run_hour = int(parts[1])
    except ValueError: pass

    if frequency == "daily":
        next_run_candidate = calc_base_time.replace(hour=run_hour, minute=run_minute, second=0, microsecond=0)
        if next_run_candidate <= calc_base_time: next_run_candidate += timedelta(days=1)
    elif frequency == "weekly":
        cron_day_of_week = 6 
        if custom_schedule_str and len(custom_schedule_str.split()) == 5 and custom_schedule_str.split()[4].isdigit():
             raw_cron_day = int(custom_schedule_str.split()[4])
             cron_day_of_week = 6 if raw_cron_day == 0 or raw_cron_day == 7 else raw_cron_day - 1
        next_run_candidate = calc_base_time.replace(hour=run_hour, minute=run_minute, second=0, microsecond=0)
        days_to_add = (cron_day_of_week - next_run_candidate.weekday() + 7) % 7
        next_run_candidate += timedelta(days=days_to_add)
        if next_run_candidate <= calc_base_time: next_run_candidate += timedelta(weeks=1)
    elif frequency == "monthly":
        cron_day_of_month = 1
        if custom_schedule_str and len(custom_schedule_str.split()) >=3 and custom_schedule_str.split()[2].isdigit():
            cron_day_of_month = int(custom_schedule_str.split()[2])
        try:
            next_run_candidate = calc_base_time.replace(day=cron_day_of_month, hour=run_hour, minute=run_minute, second=0, microsecond=0)
        except ValueError: 
            if calc_base_time.month == 12: next_run_candidate = calc_base_time.replace(year=calc_base_time.year + 1, month=1, day=1)
            else: next_run_candidate = calc_base_time.replace(month=calc_base_time.month + 1, day=1)
            next_run_candidate = next_run_candidate.replace(hour=run_hour, minute=run_minute, second=0, microsecond=0)
        if next_run_candidate <= calc_base_time:
            if next_run_candidate.month == 12: next_run_candidate = next_run_candidate.replace(year=next_run_candidate.year + 1, month=1)
            else: next_run_candidate = next_run_candidate.replace(month=next_run_candidate.month + 1)
            try: next_run_candidate = next_run_candidate.replace(day=cron_day_of_month)
            except ValueError: 
                import calendar
                last_day = calendar.monthrange(next_run_candidate.year, next_run_candidate.month)[1]
                next_run_candidate = next_run_candidate.replace(day=min(cron_day_of_month, last_day))
    elif frequency == "custom" and custom_schedule_str: return f"Custom: {custom_schedule_str} (See cron)"
    else: return "N/A (Unsupported)"
    return next_run_candidate.strftime("%Y-%m-%d %H:%M:%S %Z%z") if next_run_candidate else "N/A"

def get_storage_usage(path_to_check):
    if not path_to_check: return {"path": "N/A", "error": "Path not configured"}
    actual_path_for_df = path_to_check
    if not os.path.isdir(actual_path_for_df):
        actual_path_for_df = os.path.dirname(actual_path_for_df)
        if not os.path.exists(actual_path_for_df) or not actual_path_for_df :
             return {"path": path_to_check, "error": f"Path '{path_to_check}' or its parent does not exist."}
    if not actual_path_for_df : actual_path_for_df = '/' # Should not happen if prev check passes
    try:
        total, used, free = shutil.disk_usage(actual_path_for_df)
        return {"path_checked": actual_path_for_df, "configured_path": path_to_check,
            "total_gb": round(total / (1024**3), 2), "used_gb": round(used / (1024**3), 2),
            "free_gb": round(free / (1024**3), 2),
            "percent_used": round((used / total) * 100, 1) if total > 0 else 0 }
    except FileNotFoundError: return {"path": path_to_check, "error": f"Path '{actual_path_for_df}' not found for disk usage."}
    except Exception as e: return {"path": path_to_check, "error": str(e)}