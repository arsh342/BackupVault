# backupvault_web/app.py
from flask import Flask, render_template, jsonify
import os
from datetime import datetime
import csv # Ensure csv is imported

import data_parser 

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)

@app.route('/api/backup_summary', methods=['GET'])
def get_backup_summary_api():
    config = data_parser.get_backup_config()
    history = data_parser.get_backup_history()
    job_name = "N/A"
    if config: job_name = config.get('JOB_NAME', 'Default Backup Job')
    last_run_status = history[0]['status'] if history and history[0].get('status') else "N/A"
    total_backup_size_bytes = sum(run.get('backup_size_bytes', 0) for run in history if run.get('status', '').lower() == 'success')
    total_backup_storage_gb = round(total_backup_size_bytes / (1024**3), 2)
    next_run_display = "N/A"
    if config:
        last_run_time_iso = None
        if history and history[0].get('start_time'):
            last_run_time_iso = history[0]['start_time'].isoformat()
        next_run_display = data_parser.calculate_next_run_time(
            last_run_time_iso, config.get('FREQUENCY'), config.get('CUSTOM_CRON_SCHEDULE'))
    return jsonify({'job_name': job_name, 'total_active_jobs': 1 if config else 0, 
                    'last_backup_status': last_run_status, 
                    'total_backup_storage_gb': total_backup_storage_gb,
                    'next_scheduled_run': next_run_display})

@app.route('/api/backup_history', methods=['GET'])
def get_backup_history_api():
    history = data_parser.get_backup_history()
    serializable_history = []
    for run in history:
        run_copy = run.copy()
        if isinstance(run_copy.get('start_time'), datetime): run_copy['start_time'] = run_copy['start_time'].isoformat()
        if isinstance(run_copy.get('end_time'), datetime): run_copy['end_time'] = run_copy['end_time'].isoformat()
        serializable_history.append(run_copy)
    return jsonify(serializable_history)

@app.route('/api/backup_log/<path:log_filename>', methods=['GET'])
def get_backup_log_api(log_filename):
    if not (log_filename.startswith("run_") and log_filename.endswith(".log")):
         return jsonify({"error": "Invalid log filename format."}), 400
    content = data_parser.get_detailed_log_content(log_filename)
    return jsonify({"log_filename": log_filename, "content": content})

@app.route('/api/storage_usage', methods=['GET'])
def get_storage_usage_api():
    config = data_parser.get_backup_config()
    if not config or not config.get('DESTINATION_DIRECTORY'):
        return jsonify({"error": "Backup destination directory not found in backupvault.conf"}), 404
    dest_path = config['DESTINATION_DIRECTORY']
    usage_data = data_parser.get_storage_usage(dest_path)
    if "error" in usage_data: return jsonify(usage_data), 500
    return jsonify({'labels': [f"Volume: {usage_data.get('path_checked', dest_path)}"],
        'datasets': [{'label': 'Used GB', 'data': [usage_data.get('used_gb',0)], 
                      'backgroundColor': 'rgba(255, 99, 132, 0.7)', 'borderColor': 'rgba(255, 99, 132, 1)', 'borderWidth': 1}, 
                     {'label': 'Free GB', 'data': [usage_data.get('free_gb',0)], 
                      'backgroundColor': 'rgba(75, 192, 192, 0.7)', 'borderColor': 'rgba(75, 192, 192, 1)', 'borderWidth': 1}]})

@app.route('/')
def dashboard_page(): return render_template('dashboard.html')

if __name__ == '__main__':
    print(f"INFO: Reading config from: {data_parser.BACKUP_CONFIG_FILE}")
    print(f"INFO: Reading runs log from: {data_parser.BACKUP_RUNS_LOG_FILE}")
    print(f"INFO: Detailed logs dir: {data_parser.DETAILED_LOGS_DIR}")
    logs_base_dir = os.path.dirname(data_parser.BACKUP_RUNS_LOG_FILE)
    if not os.path.exists(logs_base_dir):
        try: os.makedirs(logs_base_dir); print(f"INFO: Created missing base log directory: {logs_base_dir}")
        except OSError as e: print(f"ERROR: Could not create base log directory {logs_base_dir}: {e}")
    
    runs_log_path = data_parser.BACKUP_RUNS_LOG_FILE
    if not os.path.exists(runs_log_path) and os.path.exists(logs_base_dir):
        try:
            with open(runs_log_path, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(['run_id', 'job_name', 'start_time', 'end_time', 'status', 
                                 'backup_size_bytes', 'source_folders_processed', 
                                 'destination_path_used', 'detailed_log_file_path', 'summary_message'])
            print(f"INFO: Created empty runs log with headers: {runs_log_path}")
        except IOError as e: print(f"ERROR: Could not create dummy runs log {runs_log_path}: {e}")
    
    app.run(debug=True, host='0.0.0.0', port=5001)