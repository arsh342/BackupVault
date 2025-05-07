#!/usr/bin/env python3
# backup_config_ui.py

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os

# --- Configuration File Path ---
CONFIG_FILE_PATH = os.path.expanduser("~/.backupvault/backupvault.conf")
APP_DIR_BASE = os.path.dirname(CONFIG_FILE_PATH)

# --- Default Values (Ensure these match keys used in backupvault.sh) ---
DEFAULT_CONFIG = {
    'JOB_NAME': 'DefaultBackupJob',
    'SOURCE_FOLDERS': '',
    'DESTINATION_DIRECTORY': os.path.expanduser("~/BackupVaultBackups"),
    'FREQUENCY': 'daily',
    'CUSTOM_CRON_SCHEDULE': '0 2 * * *',
    'COMPRESSION': 'tar.gz',
    'BACKUP_MODE': 'full',
    'RETENTION_DAYS': '30',
    'ENCRYPTION': 'none',
    'GPG_RECIPIENT': '',
    'EMAIL_NOTIFY': 'no',
    'EMAIL_ADDRESS': '',
    'EMAIL_SUBJECT_PREFIX': '[BackupVault]',
    'CLOUD_BACKUP_ENABLED': 'no',
    'RCLONE_REMOTE_NAME': '',
    'RCLONE_REMOTE_PATH': 'BackupVaultArchives/',
    'DELETE_LOCAL_AFTER_UPLOAD': 'no'
}

class BackupConfigApp:
    def __init__(self, root_window):
        self.root = root_window
        self.root.title("BackupVault Configuration")
        self.root.configure(background='#2B2B2B') # Base dark background

        self.setup_styles() # Call style setup

        # Ensure base directory for config exists
        if not os.path.exists(APP_DIR_BASE):
            try: os.makedirs(APP_DIR_BASE, exist_ok=True)
            except OSError as e:
                messagebox.showerror("Startup Error", f"Could not create app directory {APP_DIR_BASE}:\n{e}", parent=self.root)
                self.root.destroy(); return

        # --- Tkinter Variables ---
        self.vars = {}
        for key, default_value in DEFAULT_CONFIG.items():
            self.vars[key] = tk.StringVar(value=default_value)
        
        self.vars['ENCRYPTION_BOOL'] = tk.BooleanVar()
        self.vars['EMAIL_NOTIFY_BOOL'] = tk.BooleanVar()
        self.vars['CLOUD_BACKUP_ENABLED_BOOL'] = tk.BooleanVar()
        self.vars['DELETE_LOCAL_AFTER_UPLOAD_BOOL'] = tk.BooleanVar()

        self.create_ui_widgets() 
        self.load_config_to_gui() 
        self.update_dependent_widget_states() 
        self.center_window()
        self.root.resizable(False, False) # Optional: Fix window size

    def setup_styles(self):
        self.style = ttk.Style()
        try: # Use 'clam' for better customizability if available
            if 'clam' in self.style.theme_names(): self.style.theme_use('clam')
        except tk.TclError: print("Warning: Failed to set 'clam' ttk theme. Using default.")

        # Define a professional dark theme color palette
        self.bg_color = '#2B2B2B'       # Main background
        self.surface_bg = '#3C3F41'   # Widget backgrounds, slightly lighter
        self.text_color = '#D3D3D3'     # Main text (light grey)
        self.text_disabled_color = '#777777'
        self.accent_color_primary = '#007ACC' # Bright blue for primary actions/highlights
        self.accent_color_secondary = '#50A625' # Green for indicators like 'selected'
        self.border_color = '#555555'   # Subtle borders
        self.label_title_color = '#A9B7C6' # Slightly brighter for titles

        self.style.configure('.', 
            background=self.bg_color, 
            foreground=self.text_color, 
            font=('SF Pro Display', 10) # Change to a font you have, or keep system default
        )
        self.style.configure('TFrame', background=self.bg_color)
        self.style.configure('TLabel', background=self.bg_color, foreground=self.text_color)
        
        self.style.configure('TLabelframe', 
            background=self.bg_color, 
            bordercolor=self.border_color, 
            lightcolor=self.bg_color, darkcolor=self.bg_color, # For consistent border look
            relief='groove', borderwidth=1
        )
        self.style.configure('TLabelframe.Label', 
            background=self.bg_color, 
            foreground=self.accent_color_primary, # Primary accent for section titles
            font=('SF Pro Display', 11, 'bold')
        )
        
        self.style.configure('TEntry', 
            fieldbackground=self.surface_bg, 
            foreground=self.text_color, 
            insertcolor=self.text_color, # Cursor color
            borderwidth=1, 
            relief='flat'
        )
        self.style.map('TEntry', 
            fieldbackground=[('disabled', self.bg_color), ('focus', '#4A4D4F')],
            foreground=[('disabled', self.text_disabled_color)],
            relief=[('focus', 'solid')]
        )

        self.style.configure('TButton', 
            background=self.surface_bg, 
            foreground=self.text_color, 
            padding=(10, 5), 
            relief='raised', 
            borderwidth=1,
            bordercolor=self.border_color,
            font=('SF Pro Display', 10, 'normal')
        )
        self.style.map('TButton', 
            background=[('active', '#4F5254'), ('pressed', self.accent_color_primary)],
            foreground=[('pressed', '#FFFFFF')]
        )
        self.style.configure('Accent.TButton', 
            background=self.accent_color_primary, 
            foreground='#FFFFFF', 
            font=('SF Pro Display', 10, 'bold')
        )
        self.style.map('Accent.TButton', 
            background=[('active', '#008ae6'), ('pressed', '#005c99')]
        )

        self.style.configure('TCheckbutton', 
            background=self.bg_color, 
            foreground=self.text_color,
            indicatordiameter=15 # Slightly larger indicator
        )
        self.style.map('TCheckbutton', 
            indicatorcolor=[('selected', self.accent_color_secondary), ('!selected', self.surface_bg)],
            indicatorbackground=[('selected', self.surface_bg), ('!selected', self.bg_color)],
        )

        self.style.configure('TMenubutton', 
            background=self.surface_bg, 
            foreground=self.text_color, 
            arrowcolor=self.text_color, 
            relief='flat', 
            padding=(8, 5),
            borderwidth=1,
            indicatormargin=5
        )
        self.style.map('TMenubutton', 
            background=[('active', '#4F5254')]
        )
        # Style the dropdown menu (Tkinter specific options)
        self.root.option_add('*TCombobox*Listbox.background', self.surface_bg)
        self.root.option_add('*TCombobox*Listbox.foreground', self.text_color)
        self.root.option_add('*TCombobox*Listbox.selectBackground', self.accent_color_primary)
        self.root.option_add('*TCombobox*Listbox.selectForeground', '#FFFFFF')


    def create_ui_widgets(self):
        main_frame = ttk.Frame(self.root, padding="20 20 20 20") # More padding
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.root.columnconfigure(0, weight=1); self.root.rowconfigure(0, weight=1)
        
        current_row = 0; col_pad = 8; row_pad = 6; frame_pady = (0, 15)

        # --- Paths Section ---
        paths_frame = ttk.LabelFrame(main_frame, text="Storage & Naming", padding="15")
        paths_frame.grid(row=current_row, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=frame_pady) 
        paths_frame.columnconfigure(1, weight=1) 

        ttk.Label(paths_frame, text="Job Name:").grid(row=0, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        ttk.Entry(paths_frame, textvariable=self.vars['JOB_NAME'], width=65).grid(row=0, column=1, columnspan=2, sticky=(tk.W, tk.E), padx=col_pad, pady=row_pad)

        ttk.Label(paths_frame, text="Source Folders:").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.source_entry = ttk.Entry(paths_frame, textvariable=self.vars['SOURCE_FOLDERS'], width=65)
        self.source_entry.grid(row=1, column=1, sticky=(tk.W, tk.E), padx=col_pad, pady=row_pad)
        ttk.Button(paths_frame, text="Add Source...", command=self.browse_add_source).grid(row=1, column=2, padx=(col_pad, 0), pady=row_pad)
        ttk.Label(paths_frame, text="(Separate multiple paths with colon ':')").grid(row=2, column=1, sticky=tk.W, padx=col_pad, pady=2)
        
        ttk.Label(paths_frame, text="Destination Directory:").grid(row=3, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.dest_entry = ttk.Entry(paths_frame, textvariable=self.vars['DESTINATION_DIRECTORY'], width=65)
        self.dest_entry.grid(row=3, column=1, sticky=(tk.W, tk.E), padx=col_pad, pady=row_pad)
        ttk.Button(paths_frame, text="Browse...", command=self.browse_destination).grid(row=3, column=2, padx=(col_pad,0), pady=row_pad)
        current_row += 1

        # --- Scheduling Section ---
        schedule_frame = ttk.LabelFrame(main_frame, text="Scheduling", padding="15")
        schedule_frame.grid(row=current_row, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=frame_pady)
        schedule_frame.columnconfigure(1, weight=1)
        ttk.Label(schedule_frame, text="Frequency:").grid(row=0, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        freq_options = ['daily', 'weekly', 'monthly', 'custom']
        if self.vars['FREQUENCY'].get() not in freq_options: self.vars['FREQUENCY'].set(freq_options[0]) 
        freq_menu = ttk.OptionMenu(schedule_frame, self.vars['FREQUENCY'], self.vars['FREQUENCY'].get(), *freq_options, command=self.update_dependent_widget_states)
        freq_menu.grid(row=0, column=1, columnspan=2, sticky=(tk.W, tk.E), padx=col_pad, pady=row_pad)
        ttk.Label(schedule_frame, text="Custom Cron:").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.custom_cron_entry_widget = ttk.Entry(schedule_frame, textvariable=self.vars['CUSTOM_CRON_SCHEDULE'], width=65)
        self.custom_cron_entry_widget.grid(row=1, column=1, columnspan=2, sticky=(tk.W, tk.E), padx=col_pad, pady=row_pad)
        current_row += 1
        
        # --- Options, Security, Notifications, Cloud (Combined layout) ---
        grid_frame = ttk.Frame(main_frame)
        grid_frame.grid(row=current_row, column=0, columnspan=3, sticky=(tk.W, tk.E), pady=frame_pady)
        grid_frame.columnconfigure(0, weight=1); grid_frame.columnconfigure(1, weight=1)

        col0_frame = ttk.Frame(grid_frame) # Column for Options & Security
        col0_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), padx=(0, col_pad))
        
        options_frame = ttk.LabelFrame(col0_frame, text="Backup Format", padding="15")
        options_frame.pack(fill=tk.X, expand=True, pady=(0, frame_pady[1])) # Use frame_pady for consistency
        options_frame.columnconfigure(1, weight=1)
        ttk.Label(options_frame, text="Compression:").grid(row=0, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        comp_options = ['tar.gz', 'zip', 'none'];
        if self.vars['COMPRESSION'].get() not in comp_options: self.vars['COMPRESSION'].set(comp_options[0])
        ttk.OptionMenu(options_frame, self.vars['COMPRESSION'], self.vars['COMPRESSION'].get(), *comp_options).grid(row=0, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)
        ttk.Label(options_frame, text="Retention (Days):").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        vcmd = (self.root.register(self.validate_integer), '%P')
        ttk.Entry(options_frame, textvariable=self.vars['RETENTION_DAYS'], width=12, validate='key', validatecommand=vcmd).grid(row=1, column=1, sticky=tk.W, padx=col_pad, pady=row_pad)

        security_frame = ttk.LabelFrame(col0_frame, text="Security (GPG Encryption)", padding="15")
        security_frame.pack(fill=tk.X, expand=True)
        security_frame.columnconfigure(1, weight=1)
        self.enc_checkbox = ttk.Checkbutton(security_frame, text="Enable GPG Encryption", variable=self.vars['ENCRYPTION_BOOL'], command=self.update_dependent_widget_states)
        self.enc_checkbox.grid(row=0, column=0, columnspan=2, sticky=tk.W, padx=col_pad, pady=row_pad)
        ttk.Label(security_frame, text="GPG Recipient ID:").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.gpg_recipient_entry_widget = ttk.Entry(security_frame, textvariable=self.vars['GPG_RECIPIENT'], width=35)
        self.gpg_recipient_entry_widget.grid(row=1, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)

        col1_frame = ttk.Frame(grid_frame) # Column for Notifications & Cloud
        col1_frame.grid(row=0, column=1, sticky=(tk.W, tk.E, tk.N, tk.S), padx=(col_pad, 0))

        notify_frame = ttk.LabelFrame(col1_frame, text="Notifications", padding="15")
        notify_frame.pack(fill=tk.X, expand=True, pady=(0, frame_pady[1]))
        notify_frame.columnconfigure(1, weight=1)
        self.email_notify_checkbox = ttk.Checkbutton(notify_frame, text="Enable Email Notifications", variable=self.vars['EMAIL_NOTIFY_BOOL'], command=self.update_dependent_widget_states)
        self.email_notify_checkbox.grid(row=0, column=0, columnspan=2, sticky=tk.W, padx=col_pad, pady=row_pad)
        ttk.Label(notify_frame, text="Email Address:").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.email_addr_entry_widget = ttk.Entry(notify_frame, textvariable=self.vars['EMAIL_ADDRESS'], width=35)
        self.email_addr_entry_widget.grid(row=1, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)
        ttk.Label(notify_frame, text="Email Subject Prefix:").grid(row=2, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.email_subj_entry_widget = ttk.Entry(notify_frame, textvariable=self.vars['EMAIL_SUBJECT_PREFIX'], width=35)
        self.email_subj_entry_widget.grid(row=2, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)

        cloud_frame = ttk.LabelFrame(col1_frame, text="Cloud Backup (via rclone)", padding="15")
        cloud_frame.pack(fill=tk.X, expand=True)
        cloud_frame.columnconfigure(1, weight=1)
        self.cloud_backup_checkbox = ttk.Checkbutton(cloud_frame, text="Enable Cloud Backup", variable=self.vars['CLOUD_BACKUP_ENABLED_BOOL'], command=self.update_dependent_widget_states)
        self.cloud_backup_checkbox.grid(row=0, column=0, columnspan=2, sticky=tk.W, padx=col_pad, pady=row_pad)
        ttk.Label(cloud_frame, text="Rclone Remote Name:").grid(row=1, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.rclone_remote_entry_widget = ttk.Entry(cloud_frame, textvariable=self.vars['RCLONE_REMOTE_NAME'], width=35)
        self.rclone_remote_entry_widget.grid(row=1, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)
        ttk.Label(cloud_frame, text="Remote Path (on cloud):").grid(row=2, column=0, sticky=tk.W, padx=col_pad, pady=row_pad)
        self.rclone_path_entry_widget = ttk.Entry(cloud_frame, textvariable=self.vars['RCLONE_REMOTE_PATH'], width=35)
        self.rclone_path_entry_widget.grid(row=2, column=1, sticky=(tk.W,tk.E), padx=col_pad, pady=row_pad)
        self.delete_local_checkbox_widget = ttk.Checkbutton(cloud_frame, text="Delete local after successful upload", variable=self.vars['DELETE_LOCAL_AFTER_UPLOAD_BOOL'])
        self.delete_local_checkbox_widget.grid(row=3, column=0, columnspan=2, sticky=tk.W, padx=col_pad, pady=row_pad)
        current_row +=1

        # Action Buttons
        button_frame = ttk.Frame(main_frame) 
        button_frame.grid(row=current_row, column=0, columnspan=3, sticky=tk.E, pady=(row_pad*2, 0)) # pady top only
        save_button = ttk.Button(button_frame, text="Save Configuration", command=self.save_config_and_exit, style="Accent.TButton")
        save_button.pack(side=tk.RIGHT, padx=(col_pad, 0))
        ttk.Button(button_frame, text="Cancel", command=self.root.destroy).pack(side=tk.RIGHT)

    def update_dependent_widget_states(self, event=None):
        # Custom Cron Entry
        if hasattr(self, 'custom_cron_entry_widget'):
            is_custom_freq = self.vars['FREQUENCY'].get() == 'custom'
            self.custom_cron_entry_widget.config(state=tk.NORMAL if is_custom_freq else tk.DISABLED)
            if not is_custom_freq: # Auto-fill standard cron if not custom
                freq = self.vars['FREQUENCY'].get()
                if freq == "daily": self.vars['CUSTOM_CRON_SCHEDULE'].set(DEFAULT_CONFIG['CUSTOM_CRON_SCHEDULE'])
                elif freq == "weekly": self.vars['CUSTOM_CRON_SCHEDULE'].set("0 2 * * 0")
                elif freq == "monthly": self.vars['CUSTOM_CRON_SCHEDULE'].set("0 2 1 * *")
        
        # GPG Recipient Entry
        if hasattr(self, 'gpg_recipient_entry_widget'):
            self.gpg_recipient_entry_widget.config(state=tk.NORMAL if self.vars['ENCRYPTION_BOOL'].get() else tk.DISABLED)

        # Email Fields
        email_fields_state = tk.NORMAL if self.vars['EMAIL_NOTIFY_BOOL'].get() else tk.DISABLED
        if hasattr(self, 'email_addr_entry_widget'): self.email_addr_entry_widget.config(state=email_fields_state)
        if hasattr(self, 'email_subj_entry_widget'): self.email_subj_entry_widget.config(state=email_fields_state)

        # Cloud Backup Fields
        cloud_fields_state = tk.NORMAL if self.vars['CLOUD_BACKUP_ENABLED_BOOL'].get() else tk.DISABLED
        if hasattr(self, 'rclone_remote_entry_widget'): self.rclone_remote_entry_widget.config(state=cloud_fields_state)
        if hasattr(self, 'rclone_path_entry_widget'): self.rclone_path_entry_widget.config(state=cloud_fields_state)
        if hasattr(self, 'delete_local_checkbox_widget'): self.delete_local_checkbox_widget.config(state=cloud_fields_state)

    # --- Methods (validate_integer, center_window, browse_add_source, browse_destination, load_config_to_gui, save_config_and_exit) ---
    # (These remain largely the same as the last "complete file" for backup_config_ui.py,
    #  ensure they are correctly implemented as provided in that version.)
    def validate_integer(self, P):
        if P == "" or P.isdigit(): return True
        else: self.root.bell(); return False
    def center_window(self):
        self.root.update_idletasks() 
        width = self.root.winfo_reqwidth(); height = self.root.winfo_reqheight() # Use reqwidth/height before window is mapped
        x = (self.root.winfo_screenwidth() // 2) - (width // 2)
        y = (self.root.winfo_screenheight() // 2) - (height // 2)
        self.root.geometry(f'{width}x{height}+{x}+{y-50}') # Move up a bit more
    def browse_add_source(self):
        directory = filedialog.askdirectory(title="Select Source Folder to Add", initialdir=os.path.expanduser("~"), parent=self.root)
        if directory:
            current_sources = self.vars['SOURCE_FOLDERS'].get()
            sources_list = [s for s in current_sources.split(':') if s] # Handle empty strings
            if directory not in sources_list:
                sources_list.append(directory)
                self.vars['SOURCE_FOLDERS'].set(":".join(sources_list))
    def browse_destination(self):
        initial_dir = self.vars['DESTINATION_DIRECTORY'].get()
        if not initial_dir or not os.path.isdir(initial_dir): initial_dir = os.path.expanduser("~")
        directory = filedialog.askdirectory(title="Select Destination Directory", initialdir=initial_dir, parent=self.root)
        if directory: self.vars['DESTINATION_DIRECTORY'].set(directory)
    def load_config_to_gui(self):
        temp_config = DEFAULT_CONFIG.copy()
        if os.path.exists(CONFIG_FILE_PATH) and os.path.getsize(CONFIG_FILE_PATH) > 0:
            try:
                with open(CONFIG_FILE_PATH, 'r', encoding='utf-8') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            key, value_with_quotes = line.split("=", 1)
                            key = key.strip().upper(); value = value_with_quotes.strip()
                            if (value.startswith('"') and value.endswith('"')) or \
                               (value.startswith("'") and value.endswith("'")): value = value[1:-1]
                            if key in temp_config: temp_config[key] = value
            except Exception as e: print(f"Error reading config file '{CONFIG_FILE_PATH}': {e}")
        
        for key_default in DEFAULT_CONFIG:
            tk_var_name = key_default
            bool_var_name = key_default + "_BOOL"
            config_value = temp_config.get(tk_var_name.upper(), DEFAULT_CONFIG[tk_var_name])
            if tk_var_name in self.vars: self.vars[tk_var_name].set(config_value)
            if bool_var_name in self.vars:
                if key_default in ['EMAIL_NOTIFY', 'CLOUD_BACKUP_ENABLED', 'DELETE_LOCAL_AFTER_UPLOAD']:
                     self.vars[bool_var_name].set(config_value.lower() == 'yes')
                elif key_default == 'ENCRYPTION': # Special for ENCRYPTION
                     self.vars['ENCRYPTION_BOOL'].set(config_value.lower() == 'gpg')

    def save_config_and_exit(self):
        if not self.vars['SOURCE_FOLDERS'].get().strip(): messagebox.showerror("Validation Error", "Source Folders empty.", parent=self.root); return
        if not self.vars['DESTINATION_DIRECTORY'].get().strip(): messagebox.showerror("Validation Error", "Destination Directory empty.", parent=self.root); return
        try:
            if int(self.vars['RETENTION_DAYS'].get()) < 0: raise ValueError()
        except ValueError: messagebox.showerror("Validation Error", "Retention Days must be >= 0.", parent=self.root); return
        config_to_save = {}
        for key_default in DEFAULT_CONFIG:
            bool_var_name = key_default + "_BOOL"
            if key_default in ['EMAIL_NOTIFY', 'CLOUD_BACKUP_ENABLED', 'DELETE_LOCAL_AFTER_UPLOAD']:
                config_to_save[key_default] = 'yes' if self.vars[bool_var_name].get() else 'no'
            elif key_default == 'ENCRYPTION':
                 config_to_save[key_default] = 'gpg' if self.vars['ENCRYPTION_BOOL'].get() else 'none'
            else: config_to_save[key_default] = self.vars[key_default].get()

        if config_to_save['ENCRYPTION'] == 'gpg' and not config_to_save['GPG_RECIPIENT'].strip() : messagebox.showerror("Validation Error", "GPG Recipient empty for encryption.", parent=self.root); return
        elif config_to_save['ENCRYPTION'] == 'none': config_to_save['GPG_RECIPIENT'] = '' 
        if config_to_save['EMAIL_NOTIFY'] == 'yes' and not config_to_save['EMAIL_ADDRESS'].strip(): messagebox.showerror("Validation Error", "Email Address empty for notifications.", parent=self.root); return
        elif config_to_save['EMAIL_NOTIFY'] == 'no': config_to_save['EMAIL_ADDRESS'] = ''; config_to_save['EMAIL_SUBJECT_PREFIX'] = DEFAULT_CONFIG['EMAIL_SUBJECT_PREFIX']
        if config_to_save['CLOUD_BACKUP_ENABLED'] == 'yes':
            if not config_to_save['RCLONE_REMOTE_NAME'].strip(): messagebox.showerror("Validation Error", "Rclone Remote Name empty.", parent=self.root); return
            if not config_to_save['RCLONE_REMOTE_PATH'].strip(): messagebox.showerror("Validation Error", "Rclone Remote Path empty.", parent=self.root); return
        elif config_to_save['CLOUD_BACKUP_ENABLED'] == 'no':
            config_to_save['RCLONE_REMOTE_NAME'] = ''; config_to_save['RCLONE_REMOTE_PATH'] = ''; config_to_save['DELETE_LOCAL_AFTER_UPLOAD'] = 'no'
        freq = config_to_save['FREQUENCY']
        if freq == 'custom' and not config_to_save['CUSTOM_CRON_SCHEDULE'].strip(): messagebox.showerror("Validation Error", "Custom Cron Schedule empty.", parent=self.root); return
        elif freq != 'custom':
            if freq == "daily": config_to_save['CUSTOM_CRON_SCHEDULE'] = DEFAULT_CONFIG['CUSTOM_CRON_SCHEDULE']
            elif freq == "weekly": config_to_save['CUSTOM_CRON_SCHEDULE'] = "0 2 * * 0"
            elif freq == "monthly": config_to_save['CUSTOM_CRON_SCHEDULE'] = "0 2 1 * *"
        try:
            os.makedirs(APP_DIR_BASE, exist_ok=True)
            with open(CONFIG_FILE_PATH, 'w', encoding='utf-8') as f:
                for key, value in config_to_save.items(): f.write(f'{key.upper()}="{value}"\n') 
            messagebox.showinfo("Success", f"Configuration saved:\n{CONFIG_FILE_PATH}", parent=self.root)
            self.root.destroy() 
        except Exception as e: messagebox.showerror("Save Error", f"Failed to save config:\n{e}", parent=self.root)


if __name__ == "__main__":
    root = tk.Tk()
    app = BackupConfigApp(root)
    root.mainloop()