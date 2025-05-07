// backupvault_web/static/js/main.js

document.addEventListener('DOMContentLoaded', function() {
    // --- Footer Year and Current Time Update ---
    const currentYearElem = document.getElementById('currentYear');
    if (currentYearElem) {
        currentYearElem.textContent = new Date().getFullYear();
    }
    
    const currentTimeDisplayElem = document.getElementById('currentTimeDisplay');
    function updateCurrentTime() {
        if (currentTimeDisplayElem) {
            currentTimeDisplayElem.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
        }
    }
    if (currentTimeDisplayElem) { // Check if element exists before trying to update
        updateCurrentTime();
        setInterval(updateCurrentTime, 1000); // Update every second
    }

    // --- Helper function to safely set text content ---
    function setTextContent(elementId, text, defaultValue = 'N/A') {
        const element = document.getElementById(elementId);
        if (element) {
            element.textContent = (text === undefined || text === null || text === '') ? defaultValue : String(text);
        } else {
            // console.warn(`[setTextContent] Element with ID '${elementId}' not found.`);
        }
    }

    // --- Generic Fetch Data Helper ---
    async function fetchData(url, errorCallbackMessage = "Failed to load data.") {
        try {
            const response = await fetch(url);
            if (!response.ok) {
                let errorText = `HTTP error ${response.status}`;
                try {
                    const errorJson = await response.json();
                    errorText += `: ${errorJson.error || response.statusText}`;
                } catch (e) { /* ignore if response body is not json */ }
                throw new Error(errorText);
            }
            return await response.json();
        } catch (error) {
            console.error(`Error fetching from ${url}:`, error);
            // Optionally display a generic error message on the UI here
            // For example, find an error display element and set its textContent
            // document.getElementById('global-error-display').textContent = `${errorCallbackMessage}: ${error.message}`;
            throw error; // Re-throw to be caught by specific callers if needed
        }
    }

    // --- API Call: Backup Summary ---
    fetchData('/api/backup_summary', "Failed to load summary statistics.")
        .then(data => {
            setTextContent('job-name', data.job_name);
            setTextContent('last-backup-status', data.last_backup_status);
            setTextContent('total-backup-storage', data.total_backup_storage_gb !== undefined ? data.total_backup_storage_gb.toFixed(2) : '0.00');
            setTextContent('next-scheduled-run', data.next_scheduled_run);

            // Also update the simpler "Next Backup Task" section if present
            const nextJobNameDisplay = document.getElementById('next-job-name-display');
            const nextRunTimeDisplay = document.getElementById('next-run-time-display');
            if(nextJobNameDisplay) setTextContent('next-job-name-display', data.job_name);
            if(nextRunTimeDisplay) setTextContent('next-run-time-display', data.next_scheduled_run);
        })
        .catch(error => {
            // Set error states for summary cards
            setTextContent('job-name', 'Error');
            setTextContent('last-backup-status', 'Error');
            setTextContent('total-backup-storage', 'Error');
            setTextContent('next-scheduled-run', 'Error');
        });

    // --- API Call: Backup History ---
    fetchData('/api/backup_history', "Failed to load backup history.")
        .then(data => {
            const historyTableBody = document.querySelector('#backup-history-table tbody');
            if (!historyTableBody) {
                console.warn("Backup history table body not found.");
                return;
            }
            historyTableBody.innerHTML = ''; // Clear existing rows (like "Loading history...")

            if (!data || data.length === 0) {
                historyTableBody.innerHTML = '<tr><td colspan="8" style="text-align:center; color: var(--text-muted-color);">No backup history found. Run a backup using backupvault.sh!</td></tr>';
                return;
            }

            data.forEach(run => {
                const row = historyTableBody.insertRow();
                row.insertCell().textContent = run.run_id || 'N/A';
                row.insertCell().textContent = run.job_name || 'N/A';
                row.insertCell().textContent = run.start_time ? new Date(run.start_time).toLocaleString() : 'N/A';
                row.insertCell().textContent = run.end_time ? new Date(run.end_time).toLocaleString() : 'N/A';
                
                const statusCell = row.insertCell();
                statusCell.textContent = run.status || 'N/A';
                if (run.status) {
                    const statusText = run.status.toLowerCase();
                    if (statusText.includes('success')) {
                        statusCell.style.color = 'var(--success-color)'; // Use CSS variable
                        statusCell.style.fontWeight = 'bold';
                    } else if (statusText.includes('fail')) {
                        statusCell.style.color = 'var(--error-color)'; // Use CSS variable
                        statusCell.style.fontWeight = 'bold';
                    } else if (statusText.includes('running')) {
                        statusCell.style.color = 'var(--accent-color-1)'; // Or another appropriate color
                        statusCell.style.fontStyle = 'italic';
                    }
                }

                row.insertCell().textContent = run.backup_size_bytes ? (run.backup_size_bytes / (1024*1024)).toFixed(2) + ' MB' : '0.00 MB';
                
                const summaryCell = row.insertCell();
                summaryCell.textContent = run.summary_message ? (run.summary_message.length > 45 ? run.summary_message.substring(0, 42) + '...' : run.summary_message) : '-';
                if(run.summary_message) summaryCell.title = run.summary_message; // Show full summary on hover

                const logCell = row.insertCell();
                if (run.detailed_log_file_path) {
                    const logLink = document.createElement('a');
                    logLink.href = "#";
                    logLink.textContent = "View Log";
                    logLink.className = "log-link"; 
                    logLink.dataset.logFile = run.detailed_log_file_path;
                    logLink.addEventListener('click', function(e) {
                        e.preventDefault();
                        viewLog(this.dataset.logFile);
                    });
                    logCell.appendChild(logLink);
                } else {
                    logCell.textContent = "No Details";
                    logCell.style.color = 'var(--text-muted-color)';
                }
            });
        })
        .catch(error => {
            const historyTableBody = document.querySelector('#backup-history-table tbody');
            if (historyTableBody) historyTableBody.innerHTML = '<tr><td colspan="8" style="text-align:center; color: var(--error-color);">Error loading backup history.</td></tr>';
        });

    // --- API Call: Storage Usage Chart ---
    let storageChartInstance = null; 
    fetchData('/api/storage_usage', "Failed to load storage usage data.")
        .then(chartData => {
            const chartCanvas = document.getElementById('storageUsageChart');
            if (!chartCanvas) {
                 console.warn("Storage usage chart canvas not found.");
                 return;
            }
            const chartContainer = chartCanvas.parentElement; // Assuming canvas is wrapped
            if (chartData.error) {
                console.error("Error from /api/storage_usage: ", chartData.error);
                if(chartContainer) chartContainer.innerHTML = `<p style="color:var(--error-color); text-align:center; padding: 20px 0;">Could not load storage data: ${chartData.error}</p>`;
                return;
            }
            if (window.storageChartInstance) { window.storageChartInstance.destroy(); }

            // Updated colors to match our new theme
            const colorUsed = 'rgba(244, 114, 182, 0.7)'; // Pink accent
            const borderUsed = 'rgba(244, 114, 182, 1)';
            const colorFree = 'rgba(56, 189, 248, 0.7)';  // Blue accent
            const borderFree = 'rgba(56, 189, 248, 1)';
            const gridColor = 'rgba(148, 163, 184, 0.1)'; 
            const textColor = getComputedStyle(document.body).getPropertyValue('--text-color').trim() || '#e2e8f0';

            window.storageChartInstance = new Chart(chartCanvas.getContext('2d'), {
                type: 'bar',
                data: {
                    labels: chartData.labels || ["Storage Volume"],
                    datasets: [
                        {
                            label: 'Used GB',
                            data: chartData.datasets && chartData.datasets[0] ? chartData.datasets[0].data : [],
                            backgroundColor: colorUsed,
                            borderColor: borderUsed,
                            borderWidth: 1,
                            barPercentage: 0.6,
                            categoryPercentage: 0.7
                        }, 
                        {
                            label: 'Free GB',
                            data: chartData.datasets && chartData.datasets[1] ? chartData.datasets[1].data : [],
                            backgroundColor: colorFree,
                            borderColor: borderFree,
                            borderWidth: 1,
                            barPercentage: 0.6,
                            categoryPercentage: 0.7
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    indexAxis: 'y', 
                    scales: {
                        x: { 
                            beginAtZero: true,
                            title: { display: true, text: 'Gigabytes (GB)', color: textColor, font: { size: 13, weight: '500' } },
                            ticks: { color: textColor, font: { size: 11 } },
                            grid: { color: gridColor, borderColor: gridColor, drawBorder: false }
                        },
                        y: { 
                             ticks: { color: textColor, font: { size: 11 } },
                             grid: { display: false } // Often cleaner for horizontal bars
                         }
                    },
                    plugins: {
                        legend: { 
                            display: true, 
                            position: 'top', 
                            labels: { color: textColor, font: { size: 12}, boxWidth: 15, padding: 20 }
                        },
                        tooltip: {
                            backgroundColor: 'rgba(15, 23, 42, 0.9)', // Darker tooltip for contrast
                            titleColor: textColor,
                            bodyColor: textColor,
                            borderColor: 'rgba(148, 163, 184, 0.2)',
                            borderWidth: 1,
                            padding: 10,
                            callbacks: {
                                label: function(context) {
                                    return ` ${context.dataset.label || ''}: ${context.parsed.x !== null ? context.parsed.x.toFixed(2) : 'N/A'} GB`;
                                }
                            }
                        }
                    }
                }
            });
        })
        .catch(error => {
            const chartCanvas = document.getElementById('storageUsageChart');
            if (chartCanvas) chartCanvas.parentElement.innerHTML = '<p style="color:var(--error-color); text-align:center; padding: 20px 0;">Error loading storage usage chart.</p>';
        });

    // --- Log Viewer Modal Logic ---
    const logModal = document.getElementById('logModal');
    const logModalContent = document.getElementById('logModalContent');
    const logModalFilename = document.getElementById('logModalFilename');
    const closeButton = document.querySelector('#logModal .close-button');

    if (logModal && closeButton && logModalContent && logModalFilename) {
        closeButton.onclick = function() { logModal.style.display = "none"; }
        window.onclick = function(event) {
            if (event.target == logModal) { logModal.style.display = "none"; }
        }
    } else {
        console.warn("Log modal, its content, filename display, or close button not found. Log viewing might be impaired.");
    }

    // Using textContent is generally safer as it doesn't parse HTML
    // For <pre> tags, textContent preserves whitespace and newlines correctly.
    function viewLog(logFilename) {
        if (!logFilename || !logModal || !logModalContent || !logModalFilename) {
            alert("Error: Cannot display log. Modal components missing or no log file specified.");
            return;
        }
        logModalFilename.textContent = logFilename;
        logModalContent.textContent = "Loading log data..."; // Show loading state
        logModal.style.display = "block";

        fetchData(`/api/backup_log/${encodeURIComponent(logFilename)}`, `Failed to load log: ${logFilename}`)
            .then(data => {
                if (data.error) {
                    logModalContent.textContent = `Error fetching log:\n${data.error}`;
                } else {
                    logModalContent.textContent = data.content || "Log content is empty or unavailable.";
                }
            })
            .catch(error => {
                 logModalContent.textContent = `Could not load log content.\n${error.message || "Network error or API failure."}`;
            });
    }
});