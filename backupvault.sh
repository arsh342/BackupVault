#!/bin/bash

# BackupVault (Local Configuration & Backup Execution Script)
# Tagline: Store and restore effortlessly

# --- Configuration & Log Paths ---
APP_DIR_BASE="$HOME/.backupvault"
CONFIG_FILE="$APP_DIR_BASE/backupvault.conf"
LOG_DIR_BASE="$APP_DIR_BASE/logs"
RUNS_LOG_CSV="$LOG_DIR_BASE/backup_runs.csv"
DETAILED_LOGS_DIR="$LOG_DIR_BASE/details"
CURRENT_RUN_DETAILED_LOG=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SCRIPT_FULL_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
PYTHON_GUI_SCRIPT="$SCRIPT_DIR/backup_config_ui.py"

# --- Global Configuration Variables (defaults, populated by load_config) ---
JOB_NAME="DefaultBackupJob"
SOURCE_FOLDERS=""
DESTINATION_DIRECTORY=""
FREQUENCY="daily"; CUSTOM_CRON_SCHEDULE="0 2 * * *"
COMPRESSION="tar.gz"; BACKUP_MODE="full"
RETENTION_DAYS="30" # Actual cleanup logic still a TODO
ENCRYPTION="none"; GPG_RECIPIENT=""
# Email Notification Settings
EMAIL_NOTIFY="no"; EMAIL_ADDRESS=""; EMAIL_SUBJECT_PREFIX="[BackupVault]"
# Cloud Backup Settings
CLOUD_BACKUP_ENABLED="no"; RCLONE_REMOTE_NAME=""; RCLONE_REMOTE_PATH="BackupVault/"
DELETE_LOCAL_AFTER_UPLOAD="no"

# --- Ensure Base Directories Exist ---
mkdir -p "$APP_DIR_BASE"; mkdir -p "$LOG_DIR_BASE"; mkdir -p "$DETAILED_LOGS_DIR"

# --- Logging Functions ---
# (log_message_detailed and log_run_summary remain the same as previous version)
log_message_detailed() {
    local message="$1"
    local log_target="${CURRENT_RUN_DETAILED_LOG:-$LOG_DIR_BASE/backupvault_script_operations.log}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_target"
}
log_run_summary() {
    local run_id="$1"; local job_name_arg="$2"; local start_time_iso="$3"; local end_time_iso="$4"
    local status="$5"; local backup_size_bytes="$6"; local source_folders_processed="$7"
    local destination_path_used_base="$8"; local detailed_log_filename="$9"; local summary_message="${10}"
    if [[ ! -f "$RUNS_LOG_CSV" ]] || [[ ! -s "$RUNS_LOG_CSV" ]]; then
        echo "run_id,job_name,start_time,end_time,status,backup_size_bytes,source_folders_processed,destination_path_used,detailed_log_file_path,summary_message" > "$RUNS_LOG_CSV"
    fi
    echo "\"$run_id\",\"$job_name_arg\",\"$start_time_iso\",\"$end_time_iso\",\"$status\",\"$backup_size_bytes\",\"$source_folders_processed\",\"$destination_path_used_base\",\"$detailed_log_filename\",\"$summary_message\"" >> "$RUNS_LOG_CSV"
}

# --- Configuration Management ---
load_config() {
    # Reset to defaults first
    JOB_NAME="DefaultBackupJob"; SOURCE_FOLDERS=""; DESTINATION_DIRECTORY=""
    FREQUENCY="daily"; CUSTOM_CRON_SCHEDULE="0 2 * * *"; COMPRESSION="tar.gz"
    BACKUP_MODE="full"; RETENTION_DAYS="30"; ENCRYPTION="none"; GPG_RECIPIENT=""
    EMAIL_NOTIFY="no"; EMAIL_ADDRESS=""; EMAIL_SUBJECT_PREFIX="[BackupVault]"
    CLOUD_BACKUP_ENABLED="no"; RCLONE_REMOTE_NAME=""; RCLONE_REMOTE_PATH="BackupVault/"
    DELETE_LOCAL_AFTER_UPLOAD="no"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_message_detailed "[INFO] Loading config from $CONFIG_FILE"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_clean=$(echo "$line" | tr -d '\r')
            if [[ "$line_clean" =~ ^\s*# ]] || [[ "$line_clean" =~ ^\s*$ ]]; then continue; fi
            if [[ "$line_clean" =~ ^([A-Z_][A-Z0-9_]*)\s*=\s*\"(.*)\"\s*$ ]]; then
                local key="${BASH_REMATCH[1]}"; local value="${BASH_REMATCH[2]}"
                # List all known config keys here
                case "$key" in
                    JOB_NAME|SOURCE_FOLDERS|DESTINATION_DIRECTORY|FREQUENCY|CUSTOM_CRON_SCHEDULE|COMPRESSION|BACKUP_MODE|RETENTION_DAYS|ENCRYPTION|GPG_RECIPIENT|EMAIL_NOTIFY|EMAIL_ADDRESS|EMAIL_SUBJECT_PREFIX|CLOUD_BACKUP_ENABLED|RCLONE_REMOTE_NAME|RCLONE_REMOTE_PATH|DELETE_LOCAL_AFTER_UPLOAD)
                        printf -v "$key" '%s' "$value" ;;
                    *) log_message_detailed "[WARNING] Unknown key in config: '$key'" ;;
                esac
            elif [[ -n "$line_clean" ]]; then log_message_detailed "[WARNING] Malformed line in config: '$line_clean'"; fi
        done < "$CONFIG_FILE"
        log_message_detailed "[INFO] Config loading finished."
    else log_message_detailed "[INFO] No config file. Using defaults."; fi
    log_message_detailed "[DEBUG] Loaded SOURCE_FOLDERS: '$SOURCE_FOLDERS'" # For quick check
    log_message_detailed "[DEBUG] Loaded DESTINATION_DIRECTORY: '$DESTINATION_DIRECTORY'"
}

# run_wizard (calls Python GUI) and schedule_backup remain mostly the same as previous complete version
# Ensure schedule_backup uses the effective cron schedule logic from earlier
run_wizard() {
    log_message_detailed "[INFO] Launching Python Tkinter GUI from: $PYTHON_GUI_SCRIPT"
    if [[ -f "$PYTHON_GUI_SCRIPT" ]]; then
        if python3 -c "import tkinter" &>/dev/null; then
            python3 "$PYTHON_GUI_SCRIPT"
            local gui_exit_code=$?
            if [[ "$gui_exit_code" -eq 0 ]]; then
                log_message_detailed "[INFO] Python GUI exited. Configuration likely saved."
                load_config # Reload config after Python GUI saves it
                if command -v zenity &>/dev/null && zenity --question --title="Schedule Backup" --text="Config utility closed.\n(Re)schedule backup in cron now?" --ok-label="Yes, Schedule" --cancel-label="No, Later"; then
                    schedule_backup
                else log_message_detailed "[INFO] Scheduling skipped by user."; fi
            else log_message_detailed "[WARNING] Python GUI exited (code $gui_exit_code). Config might not be saved."; fi
        else log_message_detailed "[ERROR] Python3-TK (tkinter) missing."; command -v zenity &>/dev/null && zenity --error --text="<span color='red'>Error:</span> Python3-TK missing." --width=550; fi
    else log_message_detailed "[ERROR] Python GUI script missing: '$PYTHON_GUI_SCRIPT'"; command -v zenity &>/dev/null && zenity --error --text="<span color='red'>Error:</span> GUI script missing." --width=500; fi
}

schedule_backup() {
    load_config
    if [[ -z "$FREQUENCY" ]] || [[ -z "$SCRIPT_FULL_PATH" ]]; then log_message_detailed "[ERROR] Freq/path missing for schedule."; return 1; fi
    local cron_cmd="$SCRIPT_FULL_PATH run"; local eff_cron_sched="$CUSTOM_CRON_SCHEDULE"
    if [[ -z "$eff_cron_sched" ]] && [[ "$FREQUENCY" != "custom" ]]; then
        case "$FREQUENCY" in daily) eff_cron_sched="0 2 * * *";; weekly) eff_cron_sched="0 2 * * 0";; monthly) eff_cron_sched="0 2 1 * *";; esac; fi
    if [[ ("$FREQUENCY" == "custom" && -z "$eff_cron_sched") || -z "$eff_cron_sched" ]]; then log_message_detailed "[ERROR] No cron schedule string."; return 1; fi
    (crontab -l 2>/dev/null | grep -v -F "$SCRIPT_FULL_PATH run # BackupVault Job" ; echo "$eff_cron_sched $cron_cmd # BackupVault Job") | crontab -
    if [[ $? -eq 0 ]]; then log_message_detailed "[INFO] Scheduled: $eff_cron_sched $cron_cmd"; command -v zenity &>/dev/null && zenity --info --text="<span weight='bold'>Backup Scheduled!</span>\nCron: <tt>$eff_cron_sched</tt>";
    else log_message_detailed "[ERROR] Crontab schedule failed."; command -v zenity &>/dev/null && zenity --error --text="<span color='red'>Error:</span> Failed to schedule."; fi
}

# --- New Function: Send Email Notification ---
send_email() {
    local subject="$1"
    local body="$2"
    local recipient="$EMAIL_ADDRESS"

    if [[ "$EMAIL_NOTIFY" != "yes" ]] || [[ -z "$recipient" ]]; then
        log_message_detailed "[INFO] Email notification disabled or no recipient set."
        return
    fi
    if ! command -v mail &> /dev/null; then
        log_message_detailed "[ERROR] 'mail' command (mailutils) not found. Cannot send email."
        return
    fi

    log_message_detailed "[INFO] Sending email notification to $recipient..."
    echo -e "$body" | mail -s "$subject" "$recipient"
    if [[ $? -eq 0 ]]; then
        log_message_detailed "[INFO] Email sent successfully to $recipient."
    else
        log_message_detailed "[ERROR] Failed to send email to $recipient."
    fi
}

# --- New Function: Upload to Cloud (rclone) ---
upload_to_cloud_rclone() {
    local local_artifact_path="$1" # Full path to the local backup file/dir
    local artifact_basename=$(basename "$local_artifact_path")

    if [[ "$CLOUD_BACKUP_ENABLED" != "yes" ]] || [[ -z "$RCLONE_REMOTE_NAME" ]] || [[ -z "$RCLONE_REMOTE_PATH" ]]; then
        log_message_detailed "[INFO] Cloud backup disabled or rclone remote/path not configured."
        return 2 # Indicate cloud backup not attempted due to config
    fi
    if ! command -v rclone &> /dev/null; then
        log_message_detailed "[ERROR] 'rclone' command not found. Cannot upload to cloud."
        return 1 # Indicate rclone missing
    fi

    # Ensure remote path ends with a slash if it's meant to be a directory
    local remote_full_path="$RCLONE_REMOTE_NAME:${RCLONE_REMOTE_PATH%/}/" # Ensure trailing slash for dir

    log_message_detailed "[INFO] Starting cloud upload of '$artifact_basename' to '$remote_full_path'..."
    
    # Use rclone copy (or moveto if DELETE_LOCAL_AFTER_UPLOAD is "yes")
    local rclone_cmd_action="copy"
    if [[ "$DELETE_LOCAL_AFTER_UPLOAD" == "yes" ]]; then
        rclone_cmd_action="moveto"
    fi

    # rclone copy /path/to/local/file_or_dir remote:path/on/remote/
    # If local_artifact_path is a directory (e.g. COMPRESSION="none"), append its name to remote path
    # or rclone will copy its *contents* into remote_full_path.
    # For a single file artifact, this is fine.
    local rclone_destination_path="$remote_full_path"
    if [[ -d "$local_artifact_path" ]]; then # if it's a directory (e.g. no compression)
        rclone_destination_path="$remote_full_path$artifact_basename/"
    fi
    
    rclone "$rclone_cmd_action" -v --stats-one-line --stats 10s "$local_artifact_path" "$rclone_destination_path" >> "$CURRENT_RUN_DETAILED_LOG" 2>&1
    local rclone_exit_code=$?

    if [[ "$rclone_exit_code" -eq 0 ]]; then
        log_message_detailed "[INFO] Cloud upload successful for '$artifact_basename'."
        if [[ "$DELETE_LOCAL_AFTER_UPLOAD" == "yes" ]] && [[ "$rclone_cmd_action" == "copy" ]]; then
            # If we used 'copy' and wanted to delete, delete now. 'moveto' handles this.
            # This part is mainly if we forced 'copy' earlier for some reason.
            # The current logic uses 'moveto' so this explicit delete is less likely needed here.
            log_message_detailed "[INFO] Deleting local artifact '$local_artifact_path' as per policy (after copy)."
            rm -rf "$local_artifact_path"
        fi
        return 0 # Success
    else
        log_message_detailed "[ERROR] Cloud upload failed for '$artifact_basename'. rclone exit code: $rclone_exit_code. Check detailed log."
        return 1 # Failure
    fi
}


# --- Backup Logic (perform_backup) - MODIFIED ---
perform_backup() {
    load_config 
    if [[ -z "$SOURCE_FOLDERS" ]] || [[ -z "$DESTINATION_DIRECTORY" ]]; then
        CURRENT_RUN_DETAILED_LOG="${LOG_DIR_BASE}/backup_error_$(date +%s).log"; touch "$CURRENT_RUN_DETAILED_LOG"
        log_message_detailed "[FATAL_ERROR] Source or Destination directory not configured. Aborting backup."
        log_run_summary "config_error_$(date +%s)" "$JOB_NAME" "$(date --iso-8601=seconds)" "" "failed" "0" "${SOURCE_FOLDERS:-NotSet}" "${DESTINATION_DIRECTORY:-NotSet}" "config_error.log" "Fatal: Source/Destination missing"
        send_email "$EMAIL_SUBJECT_PREFIX Backup FAILED (Config Error)" "Backup job '$JOB_NAME' failed due to missing Source/Destination configuration."
        return 1
    fi

    local run_id="run_$(date +%Y%m%d_%H%M%S)"
    CURRENT_RUN_DETAILED_LOG="$DETAILED_LOGS_DIR/${run_id}.log"
    echo "BackupVault Detailed Log - Run ID: $run_id - Job: $JOB_NAME - Start: $(date)" > "$CURRENT_RUN_DETAILED_LOG"
    echo "--------------------------------------------------------------------------" >> "$CURRENT_RUN_DETAILED_LOG"
    
    local start_time_iso=$(date --iso-8601=seconds)
    local email_body="Backup Job: $JOB_NAME\nRun ID: $run_id\nStart Time: $(date)\n\n"
    log_message_detailed "[INFO] Starting backup run ID: $run_id for Job: $JOB_NAME"
    # (rest of existing perform_backup logic: sources, dest, compression, rsync/tar/zip, encryption)
    # ... (previous perform_backup logic for creating local backup artifact) ...
    # --- Ensure the following variables are correctly set by the end of local backup process: ---
    # backup_status: "success", "failed", "success_unencrypted_gpg_missing", "failed_encryption" etc.
    # final_backup_artifact_path: Full path to the created local backup file or directory.
    # backup_size_bytes: Size of the local artifact.
    # ------------------------------------------------------------------------------------------
    local backup_status="failed"; local backup_size_bytes=0
    local final_backup_artifact_path="$DESTINATION_DIRECTORY"
    local sources_to_process=$(echo "$SOURCE_FOLDERS" | sed 's/:/ /g')
    local backup_instance_name_prefix="$JOB_NAME-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$DESTINATION_DIRECTORY" || { 
        log_message_detailed "[FATAL_ERROR] Cannot create destination directory: $DESTINATION_DIRECTORY.";
        email_body+="Overall Status: FAILED (Cannot create destination directory)\n";
        log_run_summary "$run_id" "$JOB_NAME" "$start_time_iso" "" "failed" "0" "$SOURCE_FOLDERS" "$DESTINATION_DIRECTORY" "${run_id}.log" "Fatal: Cannot create dest dir";
        send_email "$EMAIL_SUBJECT_PREFIX Backup FAILED" "$email_body"; return 1; }

    # LOCAL BACKUP ARTIFACT CREATION (same as before)
    if [[ "$COMPRESSION" == "none" ]]; then
        final_backup_artifact_path="$DESTINATION_DIRECTORY/$backup_instance_name_prefix"
        mkdir -p "$final_backup_artifact_path"
        log_message_detailed "[INFO] rsync to: $final_backup_artifact_path"; email_body+="Action: Direct Sync (rsync)\n"
        rsync -avh --delete $sources_to_process "$final_backup_artifact_path/" >> "$CURRENT_RUN_DETAILED_LOG" 2>&1
        if [[ $? -eq 0 ]]; then backup_status="success"; else backup_status="failed_rsync"; fi
        if [[ -d "$final_backup_artifact_path" ]]; then backup_size_bytes=$(du -sb "$final_backup_artifact_path" | cut -f1); fi
    else
        local archive_filename_unencrypted=""; local comp_type_msg=""
        if [[ "$COMPRESSION" == "tar.gz" ]]; then archive_filename_unencrypted="${backup_instance_name_prefix}.tar.gz"; comp_type_msg="Archive (tar.gz)";
        elif [[ "$COMPRESSION" == "zip" ]]; then archive_filename_unencrypted="${backup_instance_name_prefix}.zip"; comp_type_msg="Archive (zip)"; fi
        local archive_full_path_unencrypted="$DESTINATION_DIRECTORY/$archive_filename_unencrypted"
        final_backup_artifact_path="$archive_full_path_unencrypted"
        log_message_detailed "[INFO] Archiving to: $archive_full_path_unencrypted"; email_body+="Action: $comp_type_msg\n"
        if [[ "$COMPRESSION" == "tar.gz" ]]; then tar -czvf "$archive_full_path_unencrypted" $sources_to_process >> "$CURRENT_RUN_DETAILED_LOG" 2>&1
        elif [[ "$COMPRESSION" == "zip" ]]; then
            if ! command -v zip &> /dev/null; then log_message_detailed "[ERROR] 'zip' missing."; backup_status="failed_zip_missing"; else
            zip -r "$archive_full_path_unencrypted" $sources_to_process >> "$CURRENT_RUN_DETAILED_LOG" 2>&1; fi; fi
        if [[ "$backup_status" != "failed_zip_missing" && $? -eq 0 && -f "$archive_full_path_unencrypted" ]]; then
            backup_status="success"; backup_size_bytes=$(stat -c%s "$archive_full_path_unencrypted")
            if [[ "$ENCRYPTION" == "gpg" ]] && [[ -n "$GPG_RECIPIENT" ]]; then
                email_body+="Encryption: GPG for '$GPG_RECIPIENT'\n"
                if ! command -v gpg &> /dev/null; then log_message_detailed "[ERROR] gpg missing."; backup_status="success_unencrypted_gpg_missing"
                else
                    local encrypted_path="${archive_full_path_unencrypted}.gpg"
                    log_message_detailed "[INFO] Encrypting to $encrypted_path..."
                    gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" --output "$encrypted_path" "$archive_full_path_unencrypted" >> "$CURRENT_RUN_DETAILED_LOG" 2>&1
                    if [[ $? -eq 0 && -f "$encrypted_path" ]]; then rm "$archive_full_path_unencrypted"; final_backup_artifact_path="$encrypted_path"; backup_size_bytes=$(stat -c%s "$final_backup_artifact_path")
                    else log_message_detailed "[ERROR] GPG encryption failed."; backup_status="failed_encryption"; fi; fi
            else email_body+="Encryption: None\n"; fi
        elif [[ "$backup_status" != "failed_zip_missing" ]]; then log_message_detailed "[ERROR] Archiving failed."; backup_status="failed_archive"; final_backup_artifact_path=""; fi; fi
    # END LOCAL BACKUP ARTIFACT CREATION
    email_body+="Local Backup Status: $backup_status\n"
    email_body+="Local Artifact: $(basename "${final_backup_artifact_path:-N/A}")\n"
    email_body+="Local Size: $(numfmt --to=iec-i --suffix=B $backup_size_bytes)\n\n"

    # --- Cloud Upload Step ---
    local cloud_upload_status_code=2 # 2 means not attempted or disabled
    if [[ "$backup_status" == "success" || "$backup_status" == "success_unencrypted_gpg_missing" ]] && [[ -e "$final_backup_artifact_path" ]]; then
        log_message_detailed "[INFO] Local backup successful (or partially). Proceeding to cloud upload if enabled."
        upload_to_cloud_rclone "$final_backup_artifact_path"
        cloud_upload_status_code=$? # 0 for success, 1 for rclone failure, 2 for not attempted due to config
        
        if [[ "$cloud_upload_status_code" -eq 0 ]]; then
            email_body+="Cloud Upload Status: SUCCESSFUL (rclone)\n"
            log_message_detailed "[INFO] Cloud upload marked successful in summary."
             # If DELETE_LOCAL_AFTER_UPLOAD was 'yes', rclone moveto handled it.
             # If we used 'copy' and wanted to delete, we'd rm -rf "$final_backup_artifact_path" here
        elif [[ "$cloud_upload_status_code" -eq 1 ]]; then
            email_body+="Cloud Upload Status: FAILED (rclone error)\n"
            log_message_detailed "[ERROR] Cloud upload marked as failed in summary."
            # Potentially change overall backup_status if cloud is critical
            # backup_status="failed_cloud_upload" 
        else # cloud_upload_status_code is 2 or other
            email_body+="Cloud Upload Status: SKIPPED (disabled or not configured)\n"
            log_message_detailed "[INFO] Cloud upload skipped (check config)."
        fi
    else
        log_message_detailed "[WARNING] Local backup did not succeed or artifact missing. Skipping cloud upload."
        email_body+="Cloud Upload Status: SKIPPED (local backup failed or artifact missing)\n"
    fi
    
    local end_time_iso=$(date --iso-8601=seconds)
    local final_summary_message="Local: $backup_status; Cloud: "
    if [[ "$cloud_upload_status_code" -eq 0 ]]; then final_summary_message+="OK"; 
    elif [[ "$cloud_upload_status_code" -eq 1 ]]; then final_summary_message+="FAIL";
    else final_summary_message+="SKIP"; fi
    final_summary_message+=". Artifact: $(basename "${final_backup_artifact_path:-Not created}")"
    
    email_body+="\nOverall Job Status: $final_summary_message\nEnd Time: $(date)\n\nDetailed log: $CURRENT_RUN_DETAILED_LOG"

    log_message_detailed "[INFO] $final_summary_message"
    log_message_detailed "[INFO] Final local artifact size: $backup_size_bytes bytes"
    log_message_detailed "[INFO] Backup run finished at $end_time_iso"

    log_run_summary "$run_id" "$JOB_NAME" "$start_time_iso" "$end_time_iso" "$backup_status" "$backup_size_bytes" "$SOURCE_FOLDERS" "$(dirname "${final_backup_artifact_path:-$DESTINATION_DIRECTORY}")" "${run_id}.log" "$final_summary_message"
    
    # --- Send Email Notification ---
    send_email "$EMAIL_SUBJECT_PREFIX Job: $JOB_NAME - Status: $backup_status (Cloud: $cloud_upload_status_code)" "$email_body"

    # TODO: Implement cleanup_old_backups for local and potentially cloud files

    CURRENT_RUN_DETAILED_LOG=""
    return 0
}


# --- Main Script Logic ---
main() {
    # Added mailutils, rclone to essential_cmds
    local essential_cmds=("rsync" "tar" "gzip" "date" "realpath" "mktemp" "stat" "du" "mkdir" "rm" "mv" "chmod" "grep" "sed" "cut" "tee" "cat" "echo" "python3" "crontab" "mail" "rclone" "numfmt")
    if [[ "$1" == "config" ]] || [[ "$1" == "wizard" ]] || [[ -z "$1" ]]; then
        essential_cmds+=("zenity") 
    fi
    for cmd in "${essential_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            local err_msg="[FATAL_ERROR] Essential command '$cmd' not found. Please install it."
            echo "$err_msg" >&2
            if [[ "$cmd" != "zenity" ]] && command -v zenity &> /dev/null; then
                zenity --error --title="Missing Dependency" --text="<span color='red'>Fatal:</span> Command '<tt>$cmd</tt>' not found."
            fi; exit 1; fi; done
    if [[ -z "$CURRENT_RUN_DETAILED_LOG" ]]; then CURRENT_RUN_DETAILED_LOG="$LOG_DIR_BASE/backupvault_script_operations.log"; fi

    case "$1" in
        config|wizard) log_message_detailed "[INFO] 'config' invoked."; run_wizard ;;
        run) log_message_detailed "[INFO] 'run' invoked."; perform_backup ;;
        schedule) log_message_detailed "[INFO] 'schedule' invoked."; schedule_backup ;;
        ""|--help|-h)
            echo "BackupVault Usage: $0 [command]"; echo ""
            echo "  config        Open GUI to set backup parameters."
            echo "  run           Execute backup based on current configuration."
            echo "  schedule      (Re)schedule cron job."
            echo "  (no command)  Opens configuration GUI."
            if [[ -z "$1" ]]; then log_message_detailed "[INFO] No command. Starting config GUI."; run_wizard; fi ;;
        *) log_message_detailed "[ERROR] Unknown command: '$1'."; echo "Error: Unknown command '$1'." >&2; exit 1 ;;
    esac
}
main "$@"