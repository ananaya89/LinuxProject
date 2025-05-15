#!/bin/bash

# Title: Enhanced Real-Time Process Monitor with GUI
# Author: ChatGPT (Final Enhanced Version)
# Description: Advanced Bash GUI-based Linux Process Monitoring Tool

LOG_FILE="$HOME/process_monitor.log"
TMP_FILE=$(mktemp)
TITLE="🔧 Process Monitor Pro"
ALERT_THRESHOLD=30

# Ensure dialog is installed
command -v dialog &>/dev/null || { echo "Install 'dialog' first!"; exit 1; }

log_action() {
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        dialog --title "❌ Permission Denied" --msgbox "Run this script as root (sudo)." 7 50
        exit 1
    fi
}

welcome_screen() {
    dialog --backtitle "$TITLE" --title "🎉 Welcome!" \
    --msgbox "Welcome to Process Monitor Pro!\n\n- Real-time stats\n- Alerts\n- Kill/search processes\n- Disk/Memory info\n\nUse arrow keys to navigate. 🧭" 14 60
}

search_process_by_name() {
    name=$(dialog --inputbox "Enter process name to search:" 8 40 --stdout)
    if [[ -n "$name" ]]; then
        result=$(ps aux | grep "$name" | grep -v grep | head -n 20)
        [[ -z "$result" ]] && result="No matching processes found."
        echo "$result" > "$TMP_FILE"
        dialog --title "🔍 Search Result" --textbox "$TMP_FILE" 25 80
        log_action "Searched for process '$name'"
    else
        dialog --msgbox "No input entered." 6 40
    fi
}

view_processes() {
    ps aux --sort=-%cpu | awk 'NR<=15' > "$TMP_FILE"
    dialog --title "📋 Top Processes (CPU %)" --textbox "$TMP_FILE" 25 100
    log_action "Viewed top processes"
}

monitor_high_cpu() {
    top -b -n 1 | head -n 20 > "$TMP_FILE"
    dialog --title "🔥 High CPU Usage" --textbox "$TMP_FILE" 20 80
    log_action "Checked CPU Usage"
}

kill_process() {
    pid=$(dialog --inputbox "Enter PID to kill:" 8 40 --stdout)
    [[ -z "$pid" ]] && { dialog --msgbox "No PID entered." 6 40; return; }
    if kill -9 "$pid" &>/dev/null; then
        dialog --msgbox "✅ Killed PID $pid" 6 40
        log_action "Killed PID $pid"
    else
        dialog --msgbox "❌ Failed to kill PID $pid (maybe invalid or root-only?)" 6 50
    fi
}

detailed_process_info() {
    pid=$(dialog --inputbox "Enter PID for info:" 8 40 --stdout)
    [[ -z "$pid" ]] && return
    if ps -p "$pid" > /dev/null 2>&1; then
        ps -p "$pid" -o pid,ppid,cmd,%cpu,%mem,start,time,stat > "$TMP_FILE"
        dialog --title "📃 Process Info (PID: $pid)" --textbox "$TMP_FILE" 15 70
        log_action "Viewed details of PID $pid"
    else
        dialog --msgbox "❌ PID $pid not found." 6 40
    fi
}

uptime_and_users() {
    uptime=$(uptime -p)
    users=$(who)
    echo -e "Uptime:\n$uptime\n\nUsers:\n$users" > "$TMP_FILE"
    dialog --title "⏱ Uptime & Users" --textbox "$TMP_FILE" 20 60
    log_action "Checked uptime/users"
}

disk_usage() {
    df -h > "$TMP_FILE"
    dialog --title "💽 Disk Usage" --textbox "$TMP_FILE" 20 70
    log_action "Viewed disk usage"
}

zombie_check() {
    zombies=$(ps aux | awk '$8=="Z"')
    if [[ -z "$zombies" ]]; then
        dialog --msgbox "✅ No Zombie Processes Found!" 6 40
    else
        echo "$zombies" > "$TMP_FILE"
        dialog --title "☠️ Zombie Processes" --textbox "$TMP_FILE" 20 80
    fi
    log_action "Checked zombie processes"
}
memory_usage_bar() {
    mem_info=$(free -m | awk '/^Mem:/ {print $2, $3}')
    read -r mem_total mem_used <<< "$mem_info"

    [[ -z "$mem_total" || -z "$mem_used" ]] && {
        dialog --msgbox "❌ Unable to fetch memory info." 6 40
        return
    }

    percent=$(( mem_used * 100 / mem_total ))

    # Show gauge with delay to prevent auto-close issue
    (
        echo "XXX"
        echo "$percent"
        echo "📊 Memory Usage: $percent% ($mem_used MB used of $mem_total MB total)"
        echo "XXX"
        sleep 2    # ✅ <-- this makes it work everywhere!
    ) | dialog --title "📊 Memory Usage" --gauge "Reading Memory Usage..." 10 60 0

    log_action "Checked memory usage"
}

monitor_specific_pid() {
    pid=$(dialog --inputbox "Enter PID to monitor:" 8 40 --stdout)
    [[ -z "$pid" ]] && return

    if ! ps -p "$pid" &>/dev/null; then
        dialog --msgbox "❌ PID $pid not found or not running." 6 50
        return
    fi

    (
        while ps -p "$pid" &>/dev/null; do
            ps -p "$pid" -o pid,ppid,cmd,%cpu,%mem --sort=-%cpu > "$TMP_FILE"
            sleep 2
        done
        echo "❌ PID $pid terminated." > "$TMP_FILE"
    ) &
    
    monitor_pid=$!
    dialog --title "🔎 Monitoring PID $pid (Press ESC or OK to exit)" \
           --tailbox "$TMP_FILE" 20 70

    if kill -0 "$monitor_pid" 2>/dev/null; then
        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null
    fi
    log_action "Stopped monitoring PID $pid"
}

setup_cpu_alert() {
    new_threshold=$(dialog --inputbox "Enter new CPU% threshold for alerts (current: $ALERT_THRESHOLD):" 8 50 --stdout)
    if [[ "$new_threshold" =~ ^[0-9]+$ ]]; then
        ALERT_THRESHOLD=$new_threshold
        dialog --msgbox "🔔 CPU Alert Threshold set to $ALERT_THRESHOLD%" 6 50
        log_action "Updated CPU alert threshold to $ALERT_THRESHOLD%"
    else
        dialog --msgbox "Invalid input. Please enter a numeric value." 6 50
    fi
}

auto_refresh_monitor() {
    interval=$(dialog --inputbox "Enter refresh interval (in seconds, or 0 to cancel):" 8 50 --stdout)
    [[ "$interval" == "0" || ! "$interval" =~ ^[0-9]+$ ]] && { dialog --msgbox "Cancelled auto-refresh." 6 40; return; }

    while true; do
        top -b -n 1 | head -n 20 > "$TMP_FILE"
        dialog --clear --title "♻️ Auto-Refresh Monitor" --textbox "$TMP_FILE" 20 80
        sleep "$interval"
    done
}

send_logs_email() {
    recipient=$(dialog --inputbox "Enter email to send logs to:" 8 50 --stdout)
    if [[ "$recipient" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        if command -v mail &>/dev/null; then
            mail -s "Process Monitor Logs" "$recipient" < "$LOG_FILE"
            dialog --msgbox "📤 Logs sent to $recipient (requires configured 'mail')." 6 50
            log_action "Sent logs to $recipient"
        else
            dialog --msgbox "⚠️ 'mail' command not found.\nInstall 'mailutils' to enable sending emails." 8 50
        fi
    else
        dialog --msgbox "Invalid email format." 6 40
    fi
}

main_menu() {
    while true; do
        option=$(dialog --clear --backtitle "$TITLE" --title "📊 Main Menu" --menu "Choose an action:" 22 70 14 \
            1 "📋 View Top Processes" \
            2 "🔍 Search Process by Name" \
            3 "🔥 Monitor High CPU" \
            4 "💀 Kill Process by PID" \
            5 "📃 Detailed Process Info" \
            6 "⏱ Uptime & Users" \
            7 "💽 Disk Usage" \
            8 "📊 Memory Usage Bar" \
            9 "🧟 Zombie Process Check" \
            10 "📍 Monitor Specific PID" \
            11 "⚙️ Set CPU Alert Threshold" \
            12 "♻️ Auto Refresh Monitor" \
            13 "📤 Send Logs to Email" \
            14 "🚪 Exit" --stdout)

        case $option in
            1) view_processes ;;
            2) search_process_by_name ;;
            3) monitor_high_cpu ;;
            4) kill_process ;;
            5) detailed_process_info ;;
            6) uptime_and_users ;;
            7) disk_usage ;;
            8) memory_usage_bar ;;
            9) zombie_check ;;
            10) monitor_specific_pid ;;
            11) setup_cpu_alert ;;
            12) auto_refresh_monitor ;;
            13) send_logs_email ;;
            14) break ;;
            *) break ;;
        esac
    done
}

# Start the tool
check_root
touch "$LOG_FILE"
welcome_screen
main_menu
clear
echo "Exited Process Monitor Pro. Logs at: $LOG_FILE"
