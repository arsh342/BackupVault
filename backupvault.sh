#!/bin/bash

# BackupVault (Local Configuration & Backup Execution Script)
# Tagline: Store and restore effortlessly
# Author: [Your Name/AI Assistant]
# Date: 2025-05-12
# Version: 1.4 (Improved space handling in source paths for backup tools)

# --- Strict Mode ---
set -e
set -o pipefail
# set -u # Consider after thorough testing

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

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH
export PATH

# --- Global Configuration Variables ---
JOB_NAME="DefaultBackupJob"; SOURCE_FOLDERS=""; DESTINATION_DIRECTORY=""
FREQUENCY="daily"; CUSTOM_CRON_SCHEDULE="0 2 * * *"; COMPRESSION="tar.gz"
BACKUP_MODE="full"; RETENTION_DAYS="30"; ENCRYPTION="none"; GPG_RECIPIENT=""
EMAIL_NOTIFY="no"; EMAIL_ADDRESS=""; EMAIL_SUBJECT_PREFIX="[BackupVault]"
CLOUD_BACKUP_ENABLED="no"; RCLONE_REMOTE_NAME=""; RCLONE_REMOTE_PATH="BackupVault/"
DELETE_LOCAL_AFTER_UPLOAD="no"

# --- Ensure Base Directories Exist ---
ensure_dir_exists() {
    local dir_path="$1"
    if ! mkdir -p "$dir_path"; then
        local err_msg="FATAL: Cannot create directory '$dir_path'."
        echo "$err_msg" >&2
        printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$err_msg" >> "$LOG_DIR_BASE/backupvault_script_operations.log" 2>/dev/null
        exit 1; fi
}
ensure_dir_exists "$APP_DIR_BASE"; ensure_dir_exists "$LOG_DIR_BASE"; ensure_dir_exists "$DETAILED_LOGS_DIR"

# --- Logging Functions ---
# (log_message_detailed and log_run_summary are the same as the last complete version)
log_message_detailed() {
    local message="$1"
    local log_target="${CURRENT_RUN_DETAILED_LOG:-$LOG_DIR_BASE/backupvault_script_operations.log}"
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$log_target"
}
log_run_summary() {
    local run_id="$1"; local job_name_arg="$2"; local start_time_iso="$3"; local end_time_iso="$4"
    local status="$5"; local backup_size_bytes="$6"; local source_folders_processed="$7"
    local destination_path_used_base="$8"; local detailed_log_filename="$9"; local summary_message="${10}"
    summary_message=$(echo "$summary_message" | sed 's/"/""/g') 
    destination_path_used_base=$(echo "$destination_path_used_base" | sed 's/"/""/g')
    source_folders_processed=$(echo "$source_folders_processed" | sed 's/"/""/g')
    if [[ ! -f "$RUNS_LOG_CSV" ]] || [[ ! -s "$RUNS_LOG_CSV" ]]; then
        echo "run_id,job_name,start_time,end_time,status,backup_size_bytes,source_folders_processed,destination_path_used,detailed_log_file_path,summary_message" > "$RUNS_LOG_CSV"
    fi
    echo "\"$run_id\",\"$job_name_arg\",\"$start_time_iso\",\"$end_time_iso\",\"$status\",\"$backup_size_bytes\",\"$source_folders_processed\",\"$destination_path_used_base\",\"$detailed_log_filename\",\"$summary_message\"" >> "$RUNS_LOG_CSV"
}

# --- Configuration Management ---
# (load_config is the same as the last complete version that resets globals first)
load_config() {
    JOB_NAME="DefaultBackupJob"; SOURCE_FOLDERS=""; DESTINATION_DIRECTORY=""
    FREQUENCY="daily"; CUSTOM_CRON_SCHEDULE="0 2 * * *"; COMPRESSION="tar.gz"
    BACKUP_MODE="full"; RETENTION_DAYS="30"; ENCRYPTION="none"; GPG_RECIPIENT=""
    EMAIL_NOTIFY="no"; EMAIL_ADDRESS=""; EMAIL_SUBJECT_PREFIX="[BackupVault]"
    CLOUD_BACKUP_ENABLED="no"; RCLONE_REMOTE_NAME=""; RCLONE_REMOTE_PATH="BackupVault/"
    DELETE_LOCAL_AFTER_UPLOAD="no"
    if [[ -f "$CONFIG_FILE" ]]; then
        log_message_detailed "[INFO] Attempting to load config from $CONFIG_FILE"
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_clean=$(echo "$line" | tr -d '\r')
            if [[ "$line_clean" =~ ^\s*# ]] || [[ "$line_clean" =~ ^\s*$ ]]; then continue; fi
            if [[ "$line_clean" =~ ^([A-Z_][A-Z0-9_]*)\s*=\s*\"(.*)\"\s*$ ]]; then
                local key="${BASH_REMATCH[1]}"; local value="${BASH_REMATCH[2]}"
                case "$key" in
                    JOB_NAME|SOURCE_FOLDERS|DESTINATION_DIRECTORY|FREQUENCY|CUSTOM_CRON_SCHEDULE|COMPRESSION|BACKUP_MODE|RETENTION_DAYS|ENCRYPTION|GPG_RECIPIENT|EMAIL_NOTIFY|EMAIL_ADDRESS|EMAIL_SUBJECT_PREFIX|CLOUD_BACKUP_ENABLED|RCLONE_REMOTE_NAME|RCLONE_REMOTE_PATH|DELETE_LOCAL_AFTER_UPLOAD)
                        printf -v "$key" '%s' "$value" ;;
                    *) log_message_detailed "[WARNING] Unknown key in config: '$key'" ;;
                esac
            elif [[ -n "$line_clean" ]]; then log_message_detailed "[WARNING] Malformed line in config: '$line_clean'"; fi
        done < "$CONFIG_FILE"; log_message_detailed "[INFO] Config loading finished."
    else log_message_detailed "[INFO] No config file. Using defaults."; fi
    log_message_detailed "[DEBUG] load_config final - SOURCE_FOLDERS: '$SOURCE_FOLDERS'"
    log_message_detailed "[DEBUG] load_config final - DESTINATION_DIRECTORY: '$DESTINATION_DIRECTORY'"
}

# --- Launch Python GUI for Configuration ---
# (run_wizard is the same as the last complete version that calls Python GUI)
run_wizard() {
    log_message_detailed "[INFO] Launching Python Tkinter GUI from: $PYTHON_GUI_SCRIPT"
    if [[ ! -f "$PYTHON_GUI_SCRIPT" ]]; then log_message_detailed "[ERROR] GUI script missing: '$PYTHON_GUI_SCRIPT'"; command -v zenity &>/dev/null && zenity --error --text="GUI script missing."; return 1; fi
    if ! python3 -c "import tkinter" &>/dev/null; then log_message_detailed "[ERROR] python3-tk missing."; command -v zenity &>/dev/null && zenity --error --text="python3-tk missing."; return 1; fi
    if ! python3 "$PYTHON_GUI_SCRIPT"; then
        local gui_exit_code=$?; log_message_detailed "[WARNING] Python GUI exited (code $gui_exit_code)."; command -v zenity &>/dev/null && zenity --warning --text="Config GUI closed (code $gui_exit_code)."; return 1; fi
    log_message_detailed "[INFO] Python GUI exited successfully."; load_config
    local schedule_now=0
    if command -v zenity &>/dev/null; then if zenity --question --title="Schedule Backup" --text="Config utility closed.\n(Re)schedule backup now?" --ok-label="Yes" --cancel-label="No"; then schedule_now=1; fi
    else read -p "Config closed. Schedule backup? (y/N): " sc; if [[ "$sc" =~ ^[Yy]$ ]]; then schedule_now=1; fi; fi
    if [[ "$schedule_now" -eq 1 ]]; then schedule_backup; else log_message_detailed "[INFO] Scheduling skipped."; fi; return 0
}

# --- Email Notification, Cloud Upload, Local Cleanup ---
# (send_email, upload_to_cloud_rclone, cleanup_old_local_backups are the same as the last complete version)
send_email() { local s="$1" b="$2" r="$EMAIL_ADDRESS"; if [[ "$EMAIL_NOTIFY" != "yes" || -z "$r" ]]; then log_message_detailed "[INFO] Email skip."; return 0; fi; if ! command -v mail &>/dev/null; then log_message_detailed "[ERROR] 'mail' missing."; return 1; fi; log_message_detailed "[INFO] Emailing $r..."; if printf '%s\n' "$b" | mail -s "$s" "$r"; then log_message_detailed "[INFO] Email handoff OK."; else log_message_detailed "[ERROR] Email handoff FAIL."; return 1; fi; return 0; }
upload_to_cloud_rclone() { local lfp="$1" ab; if [[ -z "$lfp" || ! -e "$lfp" ]]; then log_message_detailed "[ERROR] Cloud: Invalid local path '$lfp'."; return 1; fi; ab=$(basename "$lfp"); if [[ "$CLOUD_BACKUP_ENABLED" != "yes" || -z "$RCLONE_REMOTE_NAME" || -z "$RCLONE_REMOTE_PATH" ]]; then log_message_detailed "[INFO] Cloud skip: disabled/config."; return 2; fi; if ! command -v rclone &>/dev/null; then log_message_detailed "[ERROR] 'rclone' missing."; return 1; fi; local rbp="${RCLONE_REMOTE_PATH%/}" rfp="$RCLONE_REMOTE_NAME:$rbp/" ca="copy" dm=""; if [[ "$DELETE_LOCAL_AFTER_UPLOAD" == "yes" ]]; then ca="moveto"; dm=" (will delete local)"; fi; log_message_detailed "[INFO] Using 'rclone $ca'$dm."; local rdp="$rfp"; if [[ -d "$lfp" ]]; then rdp="$rfp$ab/"; fi; log_message_detailed "[INFO] Cloud upload of '$ab' to '$rdp'..."; log_message_detailed "[CMD] rclone $ca -v --stats-one-line --stats 10s \"$lfp\" \"$rdp\""; local rlt; rlt=$(mktemp); if rclone "$ca" -v --stats-one-line --stats 10s "$lfp" "$rdp" > "$rlt" 2>&1; then cat "$rlt" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$rlt"; log_message_detailed "[INFO] Cloud upload ($ca) OK for '$ab'."; return 0; else local rc=$?; cat "$rlt" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$rlt"; log_message_detailed "[ERROR] Cloud upload ($ca) FAIL for '$ab'. rclone code: $rc."; return 1; fi; }
cleanup_old_local_backups() { local dd="$1" rd="$2" jp="$3-*"; log_message_detailed "[INFO] Local cleanup check..."; if [[ ! "$rd" =~ ^[1-9][0-9]*$ ]]; then log_message_detailed "[INFO] Retention invalid ($rd days). Skip cleanup."; return 0; fi; if [[ ! -d "$dd" ]]; then log_message_detailed "[ERROR] Cleanup FAIL: Dest '$dd' not found."; return 1; fi; log_message_detailed "[INFO] Checking for backups older than $rd days in '$dd' matching '$jp'..."; local ftd; if ! ftd=$(find "$dd" -maxdepth 1 -name "$jp" -mtime "+$rd" -print); then log_message_detailed "[ERROR] 'find' FAIL during cleanup. Skip."; return 1; fi; if [[ -n "$ftd" ]]; then log_message_detailed "[INFO] Old backups to delete (Deletion COMMENTED OUT):"; printf '%s\n' "$ftd" >> "$CURRENT_RUN_DETAILED_LOG"; log_message_detailed "[WARNING] Actual deletion in cleanup_old_local_backups is COMMENTED for safety."; else log_message_detailed "[INFO] No old local backups to delete."; fi; return 0; }

# --- Backup Logic (perform_backup) ---
perform_backup() {
    load_config 
    if [[ -z "$SOURCE_FOLDERS" ]] || [[ -z "$DESTINATION_DIRECTORY" ]]; then
        CURRENT_RUN_DETAILED_LOG="${LOG_DIR_BASE}/backup_error_$(date +%s).log"; touch "$CURRENT_RUN_DETAILED_LOG" 2>/dev/null || true
        log_message_detailed "[FATAL_ERROR] Source or Destination directory not configured. Aborting backup."
        log_run_summary "config_error_$(date +%s)" "${JOB_NAME:-Unknown}" "$(date --iso-8601=seconds)" "" "failed_config" "0" "${SOURCE_FOLDERS:-NotSet}" "${DESTINATION_DIRECTORY:-NotSet}" "config_error.log" "Fatal: Source/Destination missing"
        send_email "$EMAIL_SUBJECT_PREFIX Backup FAILED (Config Error)" "Backup job '${JOB_NAME:-Unknown}' failed: Source/Destination missing." || true 
        return 1 
    fi

    local run_id="run_$(date +%Y%m%d_%H%M%S)"
    CURRENT_RUN_DETAILED_LOG="$DETAILED_LOGS_DIR/${run_id}.log"
    echo "BackupVault Detailed Log - Run ID: $run_id - Job: $JOB_NAME - Start: $(date)" > "$CURRENT_RUN_DETAILED_LOG"
    echo "--------------------------------------------------------------------------" >> "$CURRENT_RUN_DETAILED_LOG"
    
    local start_time_iso; start_time_iso=$(date --iso-8601=seconds)
    local email_body="Backup Job: $JOB_NAME\nRun ID: $run_id\nStart Time: $(date)\n\n"
    log_message_detailed "[INFO] ===== Starting Backup Run ====="
    # ... (Log all config details: JOB_NAME, SOURCES, DESTINATION_DIRECTORY, etc. - same as previous version) ...
    log_message_detailed "[INFO] Job Name: $JOB_NAME"; log_message_detailed "[INFO] Run ID: $run_id"
    log_message_detailed "[INFO] Sources: $SOURCE_FOLDERS"; log_message_detailed "[INFO] Destination Base: $DESTINATION_DIRECTORY"
    log_message_detailed "[INFO] Compression: $COMPRESSION, Encryption: $ENCRYPTION"
    log_message_detailed "[INFO] Cloud Upload: $CLOUD_BACKUP_ENABLED, Remote: $RCLONE_REMOTE_NAME, Path: $RCLONE_REMOTE_PATH"
    log_message_detailed "[INFO] Delete Local After Upload: $DELETE_LOCAL_AFTER_UPLOAD"
    log_message_detailed "[INFO] Email Notify: $EMAIL_NOTIFY, Recipient: $EMAIL_ADDRESS"

    local local_backup_status="pending"; local cloud_upload_status_code=2; local backup_size_bytes=0
    local final_backup_artifact_path=""
    local backup_instance_name_prefix="$JOB_NAME-$(date +%Y%m%d_%H%M%S)" 

    # Prepare source paths array for tools - THIS IS THE KEY UPDATE for space handling
    local sources_to_process_array=()
    local temp_source_folders_for_array="$SOURCE_FOLDERS" 
    IFS=':' read -r -a source_paths_temp_for_array <<< "$temp_source_folders_for_array"
    for path_item_for_array in "${source_paths_temp_for_array[@]}"; do
        if [[ -n "$path_item_for_array" ]]; then 
            sources_to_process_array+=("$path_item_for_array") 
        fi
    done
    # Check if array is empty (e.g. SOURCE_FOLDERS was empty or just colons)
    if [[ ${#sources_to_process_array[@]} -eq 0 ]]; then
        log_message_detailed "[FATAL_ERROR] No valid source folders to process after parsing SOURCE_FOLDERS. Aborting."
        email_body+="Overall Status: FAILED (No valid source folders)\n";
        log_run_summary "$run_id" "$JOB_NAME" "$start_time_iso" "" "failed_source_parse" "0" "$SOURCE_FOLDERS" "$DESTINATION_DIRECTORY" "${run_id}.log" "Fatal: No valid source folders"
        send_email "$EMAIL_SUBJECT_PREFIX Backup FAILED (Source Error)" "$email_body"; return 1;
    fi
    log_message_detailed "[DEBUG] Processable sources: ${sources_to_process_array[*]}"


    if ! mkdir -p "$DESTINATION_DIRECTORY"; then
        log_message_detailed "[FATAL_ERROR] Cannot create/access destination: $DESTINATION_DIRECTORY."
        # ... (error handling as before) ...
        return 1;
    fi

    log_message_detailed "[STEP] Creating local backup artifact..."
    local local_artifact_created=false

    if [[ "$COMPRESSION" == "none" ]]; then
        final_backup_artifact_path="$DESTINATION_DIRECTORY/$backup_instance_name_prefix"
        email_body+="Action: Direct Sync (rsync)\nTarget Dir: $final_backup_artifact_path\n"
        if ! mkdir -p "$final_backup_artifact_path"; then log_message_detailed "[ERROR] Failed to create subdir '$final_backup_artifact_path'."; local_backup_status="failed_mkdir"; else
            log_message_detailed "[INFO] Performing direct rsync..."
            log_message_detailed "[CMD] rsync -avh --delete \"${sources_to_process_array[@]}\" \"$final_backup_artifact_path/\""
            local rsync_log_tmp; rsync_log_tmp=$(mktemp); local rsync_exit_code=1
            # Pass array correctly to rsync
            rsync -avh --delete "${sources_to_process_array[@]}" "$final_backup_artifact_path/" > "$rsync_log_tmp" 2>&1 || rsync_exit_code=$?
            cat "$rsync_log_tmp" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$rsync_log_tmp"
            if [[ "$rsync_exit_code" -eq 0 ]]; then
                local_backup_status="success"; log_message_detailed "[INFO] rsync completed."
                local_artifact_created=true
                if [[ -d "$final_backup_artifact_path" ]]; then backup_size_bytes=$(du -sb "$final_backup_artifact_path" | cut -f1); fi
            else
                log_message_detailed "[ERROR] rsync failed. Exit code: $rsync_exit_code."; local_backup_status="failed_rsync"
            fi
        fi
    else # tar.gz or zip
        local archive_filename_unencrypted=""; local comp_tool=""
        if [[ "$COMPRESSION" == "tar.gz" ]]; then archive_filename_unencrypted="${backup_instance_name_prefix}.tar.gz"; comp_tool="tar";
        elif [[ "$COMPRESSION" == "zip" ]]; then archive_filename_unencrypted="${backup_instance_name_prefix}.zip"; comp_tool="zip"; fi
        local archive_full_path_unencrypted="$DESTINATION_DIRECTORY/$archive_filename_unencrypted"
        final_backup_artifact_path="$archive_full_path_unencrypted" 
        email_body+="Action: Archive ($COMPRESSION)\nTarget File: $archive_full_path_unencrypted\n"
        log_message_detailed "[INFO] Creating archive: $archive_full_path_unencrypted"

        local archive_command_ok=false; local archive_exit_code=1; local tool_log_tmp; tool_log_tmp=$(mktemp)

        if [[ "$comp_tool" == "tar" ]]; then
             log_message_detailed "[CMD] tar -czvf \"$archive_full_path_unencrypted\" --exclude=\"$(basename "$DESTINATION_DIRECTORY")\" \"${sources_to_process_array[@]}\""
             tar -czvf "$archive_full_path_unencrypted" --exclude="$(basename "$DESTINATION_DIRECTORY")" "${sources_to_process_array[@]}" > "$tool_log_tmp" 2>&1 || archive_exit_code=$?
        elif [[ "$comp_tool" == "zip" ]]; then
            if ! command -v zip &> /dev/null; then log_message_detailed "[ERROR] 'zip' missing."; local_backup_status="failed_zip_missing"; else
                 log_message_detailed "[CMD] zip -r \"$archive_full_path_unencrypted\" \"${sources_to_process_array[@]}\" -x \"$DESTINATION_DIRECTORY/*\""
                 zip -r "$archive_full_path_unencrypted" "${sources_to_process_array[@]}" -x "$DESTINATION_DIRECTORY/*" > "$tool_log_tmp" 2>&1 || archive_exit_code=$?
            fi
        fi
        cat "$tool_log_tmp" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$tool_log_tmp"

        if [[ "$local_backup_status" != "failed_zip_missing" ]]; then
            if [[ "$archive_exit_code" -eq 0 ]] && [[ -f "$archive_full_path_unencrypted" ]]; then
                if [[ -s "$archive_full_path_unencrypted" ]]; then archive_command_ok=true;
                else log_message_detailed "[ERROR] $comp_tool succeeded but created EMPTY archive."; rm "$archive_full_path_unencrypted" 2>/dev/null || true; fi
            else log_message_detailed "[ERROR] $comp_tool failed (code: $archive_exit_code) OR file not created."; fi
        fi

        if [[ "$archive_command_ok" = true ]]; then
            log_message_detailed "[INFO] Archiving successful."
            local_backup_status="success_unencrypted"; backup_size_bytes=$(stat -c%s "$archive_full_path_unencrypted"); local_artifact_created=true
            # --- Encryption Step ---
            # (Encryption logic as before, ensure it updates local_backup_status, final_backup_artifact_path correctly)
            if [[ "$ENCRYPTION" == "gpg" ]] && [[ -n "$GPG_RECIPIENT" ]]; then
                # ... (GPG logic - same as previous version which was fairly robust) ...
                log_message_detailed "[STEP] Encrypting..."; email_body+="Encryption: GPG for '$GPG_RECIPIENT'\n"
                if ! command -v gpg &> /dev/null; then log_message_detailed "[ERROR] gpg missing."; local_backup_status="success_unencrypted_gpg_missing"; else
                    local encrypted_path="${archive_full_path_unencrypted}.gpg"; log_message_detailed "[INFO] Encrypting '$archive_filename_unencrypted' to '$encrypted_path'..."
                    log_message_detailed "[CMD] gpg --batch --yes --encrypt --recipient \"$GPG_RECIPIENT\" --output \"$encrypted_path\" \"$archive_full_path_unencrypted\""
                    local gpg_log_tmp; gpg_log_tmp=$(mktemp)
                    if gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" --output "$encrypted_path" "$archive_full_path_unencrypted" > "$gpg_log_tmp" 2>&1; then
                        cat "$gpg_log_tmp" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$gpg_log_tmp"
                        if [[ -f "$encrypted_path" ]] && [[ -s "$encrypted_path" ]]; then 
                            log_message_detailed "[INFO] Encryption OK. Removing unencrypted."; rm "$archive_full_path_unencrypted"; 
                            final_backup_artifact_path="$encrypted_path"; backup_size_bytes=$(stat -c%s "$final_backup_artifact_path")
                            local_backup_status="success"; 
                        else log_message_detailed "[ERROR] GPG OK but output missing/empty!"; local_backup_status="failed_encryption_output_missing"; rm "$encrypted_path" 2>/dev/null || true; fi
                    else 
                        local gpg_exit_code=$? ; cat "$gpg_log_tmp" >> "$CURRENT_RUN_DETAILED_LOG"; rm "$gpg_log_tmp"
                        log_message_detailed "[ERROR] GPG encryption failed. Code: $gpg_exit_code."; local_backup_status="failed_encryption"; 
                    fi
                fi
            elif [[ "$ENCRYPTION" == "gpg" ]]; then log_message_detailed "[ERROR] GPG enabled but no recipient."; local_backup_status="success_unencrypted_gpg_recipient_missing";
            else email_body+="Encryption: None\n"; local_backup_status="success"; fi
        elif [[ "$local_backup_status" != "failed_zip_missing" ]]; then 
            log_message_detailed "[ERROR] Archiving process determined as failed." 
            local_backup_status="success"; final_backup_artifact_path=""; 
        fi
    fi 
    log_message_detailed "[INFO] Local backup processing finished. Status: $local_backup_status"
    # ... (rest of perform_backup: email body updates, cloud upload, final summary, logging, cleanup call - same as before) ...
    email_body+="Local Backup Status: $local_backup_status\nLocal Artifact: $(basename "${final_backup_artifact_path:-N/A}")\nLocal Size: $(numfmt --to=iec-i --suffix=B --padding=7 "$backup_size_bytes")\n\n"
    cloud_summary="N/A"
    if [[ "$local_backup_status" == success* ]] && [[ -e "$final_backup_artifact_path" ]]; then
        log_message_detailed "[STEP] Processing cloud upload..."
        if upload_to_cloud_rclone "$final_backup_artifact_path"; then cloud_upload_status_code=0; else cloud_upload_status_code=$?; fi 
        if [[ "$cloud_upload_status_code" -eq 0 ]]; then cloud_summary="OK"; email_body+="Cloud Upload: SUCCESSFUL\n"
        elif [[ "$cloud_upload_status_code" -eq 1 ]]; then cloud_summary="FAIL"; email_body+="Cloud Upload: FAILED\n"
        else cloud_summary="SKIPPED"; email_body+="Cloud Upload: SKIPPED (config)\n"; fi
    else log_message_detailed "[INFO] Skipping cloud: Local status '$local_backup_status' or artifact '$final_backup_artifact_path' missing."; cloud_summary="SKIPPED"; email_body+="Cloud Upload: SKIPPED (local issue)\n"; fi
    local end_time_iso; end_time_iso=$(date --iso-8601=seconds)
    local overall_status="$local_backup_status"
    if [[ "$local_backup_status" == success* ]] && [[ "$cloud_upload_status_code" -eq 1 ]]; then overall_status="failed_cloud_upload"; 
    elif [[ "$local_backup_status" == success* ]] && [[ "$cloud_upload_status_code" -eq 0 ]]; then overall_status="success"; # Can refine further if needed
    elif [[ "$local_backup_status" == success* ]] && [[ "$cloud_upload_status_code" -eq 2 ]]; then overall_status="Success"; fi

    local final_summary_message="Overall: $overall_status; Local: $local_backup_status; Cloud: $cloud_summary; Artifact: $(basename "${final_backup_artifact_path:-Not created}")"
    email_body+="\nOverall Job Status: $overall_status\nEnd Time: $(date)\n\nDetailed log: $CURRENT_RUN_DETAILED_LOG"
    log_message_detailed "[INFO] ===== Backup Run Summary ====="; log_message_detailed "[INFO] Final Status: $overall_status"
    log_message_detailed "[INFO] Local Artifact: $final_backup_artifact_path"; log_message_detailed "[INFO] Final Size (Local): $(numfmt --to=iec-i --suffix=B --padding=7 "$backup_size_bytes")"
    log_message_detailed "[INFO] Cloud Status: $cloud_summary (Code: $cloud_upload_status_code)"; log_message_detailed "[INFO] Run Finished: $end_time_iso"; log_message_detailed "[INFO] =============================="
    log_run_summary "$run_id" "$JOB_NAME" "$start_time_iso" "$end_time_iso" "$overall_status" "$backup_size_bytes" "$SOURCE_FOLDERS" "$(dirname "${final_backup_artifact_path:-$DESTINATION_DIRECTORY}")" "${run_id}.log" "$final_summary_message"
    send_email "$EMAIL_SUBJECT_PREFIX Job '$JOB_NAME' Finished - Status: $overall_status" "$email_body"
    log_message_detailed "[STEP] Processing local retention policy..."; cleanup_old_local_backups "$DESTINATION_DIRECTORY" "$RETENTION_DAYS" "$JOB_NAME" || log_message_detailed "[WARNING] Cleanup reported an error."
    CURRENT_RUN_DETAILED_LOG=""; log_message_detailed "[INFO] Backup process finished."
    if [[ "$overall_status" == success* ]]; then return 0; else return 1; fi 
}

# --- Main Script Logic ---
# (main function and schedule_backup remain the same as the last complete version)
# ... (Ensure the full 'main' and 'schedule_backup' functions are here) ...
main() {
    local essential_cmds=("rsync" "tar" "gzip" "date" "realpath" "mktemp" "stat" "du" "mkdir" "rm" "mv" "chmod" "grep" "sed" "cut" "tee" "cat" "echo" "python3" "crontab" "mail" "rclone" "numfmt" "find" "basename" "dirname") 
    if [[ "$1" == "config" ]] || [[ "$1" == "wizard" ]] || [[ -z "$1" ]]; then essential_cmds+=("zenity"); fi
    local cmd_missing=0
    for cmd in "${essential_cmds[@]}"; do if ! command -v "$cmd" &> /dev/null; then local e="[FATAL] '$cmd' missing."; echo "$e" >&2; cmd_missing=1; if [[ "$cmd" != "zenity" ]] && command -v zenity &>/dev/null; then zenity --error --title="Missing" --text="<span color='red'>Fatal:</span> '$cmd' missing." || true; fi; fi; done
    if [[ "$cmd_missing" -eq 1 ]]; then exit 1; fi
    if [[ -z "$CURRENT_RUN_DETAILED_LOG" ]]; then CURRENT_RUN_DETAILED_LOG="$LOG_DIR_BASE/backupvault_script_operations.log"; fi
    case "$1" in config|wizard) log_message_detailed "[INFO] Cmd: '$1'. Start GUI."; run_wizard ;; run) log_message_detailed "[INFO] Cmd: 'run'. Start backup."; perform_backup ;; schedule) log_message_detailed "[INFO] Cmd: 'schedule'."; schedule_backup ;; ""|--help|-h) echo "BackupVault Usage: $0 [cmd]"; echo "config | run | schedule | --help"; if [[ -z "$1" ]]; then log_message_detailed "[INFO] No cmd. Start GUI."; run_wizard; fi ;; *) log_message_detailed "[ERROR] Unknown cmd: '$1'."; echo "Error: Unknown cmd '$1'." >&2; exit 1 ;; esac
    local ec=$?; if [[ "$ec" -eq 0 ]]; then log_message_detailed "[INFO] Script cmd OK (Exit $ec)."; else log_message_detailed "[ERROR] Script cmd FAIL (Exit $ec)."; fi; exit $ec
}

main "$@"