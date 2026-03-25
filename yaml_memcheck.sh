#!/bin/bash

######################################################################################
# Docker Memory Resource Audit
#
# Scans a directory (default: /opt/docker) for Compose files and calculates 
# total memory limits and reservations defined across all stacks.
# Best used for setups such as Dockhand with per stack folders containing .yml files
#
# Features:
#   - Detects total system RAM (GiB) automatically.
#   - Visualizes allocation vs. a safety "Host OS Headroom" progress bar.
#   - Provides per-folder summaries and detailed container breakdowns.
#   - Identifies containers lacking memory constraints as "Unlimited".
#
# Usage:
#   Adjust DOCKER_FOLDER, OS_MARGIN_GB and optionally WARNING_BUFFER_GB 
#   in the configuration section.
#
# Created using Gemini for personal use by lupus (https://github.com/lupusaesticus)
# MIT License: Free to use at your own risk. No support or guarantees offered.
#####################################################################################

# --- CONFIGURATION ---
# Calculate total GiB with decimal precision
HOST_GB=$(free -m | awk '/Mem:/ {printf "%.1f", $2/1024}')          
OS_MARGIN_GB=8      
WARNING_BUFFER_GB=4
DOCKER_FOLDER="/opt/docker"
# ---------------------

CURRENT_RAM_MB=$(free -m | awk '/Mem:/ {print $3}')
MY_HOSTNAME=$(hostname)

find "$DOCKER_FOLDER" -name "*.yml" -o -name "*.yaml" | xargs awk -v h_gb="$HOST_GB" -v m_gb="$OS_MARGIN_GB" -v w_gb="$WARNING_BUFFER_GB" -v cur_mb="$CURRENT_RAM_MB" -v host_name="$MY_HOSTNAME" '
function human(mb) {
    if (mb == 0) return "0 MiB";
    if (mb >= 1024) return sprintf("%.2f GiB", mb/1024);
    return sprintf("%.0f MiB", mb);
}

FNR == 1 { 
    split(FILENAME, path, "/"); 
    app = path[length(path)-1]; 
    all_apps[app] = 1; 
    section = "";
    top_level = "";
}

/^[a-z]/ {
    match($0, /[a-z0-9_-]+/);
    top_level = substr($0, RSTART, RLENGTH);
}

/^[ ]{2}[a-zA-Z0-9_-]+:/ {
    if (top_level == "services") {
        match($0, /[a-zA-Z0-9_-]+/);
        tmp_service = substr($0, RSTART, RLENGTH);
        if (tmp_service !~ /^(services|version|networks|volumes|deploy|resources)$/) {
            current_service = tmp_service;
            all_services[app, current_service] = 1;
        }
    }
}

/limits:/ { section="limit" }
/reservations:/ { section="res" }

/memory:|mem_limit:|mem_reservation:/ {
    if ($1 ~ /^#/) next;
    raw_val = $NF;
    gsub(/["'\'']/, "", raw_val);
    
    # Preserve original YAML string for breakdown
    orig_val = raw_val;

    match(raw_val, /[0-9.]+/);
    num = substr(raw_val, RSTART, RLENGTH);
    unit = tolower(substr(raw_val, RSTART+RLENGTH));

    if (unit ~ /g/) mb = num * 1024;
    else if (unit ~ /m/) mb = num;
    else if (unit == "k") mb = num / 1024;
    else mb = num / 1024 / 1024;

    if ($0 ~ /mem_limit:/ || section == "limit") {
        app_limit[app] += mb;
        service_limit[app, current_service] = orig_val;
    } 
    else if ($0 ~ /mem_reservation:/ || section == "res") {
        app_res[app] += mb;
        service_res[app, current_service] = orig_val;
    }
}

END {
    RES_C="\033[0;36m"; G="\033[0;32m"; Y="\033[0;33m"; R="\033[0;31m"; NC="\033[0m";
    RED="\033[0;31m";

    t_l = 0; t_r = 0;
    for (a in app_limit) { t_l += app_limit[a]; }
    for (a in app_res) { t_r += app_res[a]; }
    
    l_gb = t_l/1024; r_gb = t_r/1024;
    p_pos = int(((h_gb - m_gb) / h_gb) * 62);
    w_start = int(((h_gb - m_gb - w_gb) / h_gb) * 62);

    if (l_gb <= (h_gb - m_gb - w_gb)) LIM_COLOR=G;
    else if (l_gb <= (h_gb - m_gb)) LIM_COLOR=Y;
    else LIM_COLOR=R;

    title = "Docker Memory Resource Audit"
    subtitle = host_name
    print "\n****************************************************************";
    
    t_pad_l = int((62 - length(title)) / 2);
    t_pad_r = 62 - t_pad_l - length(title);
    printf "*%*s%s%*s*\n", t_pad_l, "", title, t_pad_r, "";
    
    s_pad_l = int((62 - length(subtitle)) / 2);
    s_pad_r = 62 - s_pad_l - length(subtitle);
    printf "*%*s%s%*s*\n", s_pad_l, "", subtitle, s_pad_r, "";
    
    print "****************************************************************\n";

    header_text = sprintf(" System RAM: %s / %.1f GiB ", human(cur_mb), h_gb);
    padding = (64 - length(header_text)) / 2;
    for(i=0; i<int(padding); i++) printf "=";
    printf "%s", header_text;
    for(i=0; i<int(padding + 0.5); i++) printf "=";
    printf "\n";

    printf "[" ;
    for(i=1; i<=62; i++) {
        seg_gb = (i/62) * h_gb;
        if (i <= w_start) C=G; else if (i <= p_pos) C=Y; else C=R;
        if (i == p_pos) {
            if (l_gb >= seg_gb) printf "%s|%s", C, NC; else printf "|";
        } 
        else if (r_gb >= seg_gb) printf "%s#%s", RES_C, NC;
        else if (l_gb >= seg_gb) printf "%s#%s", C, NC;
        else printf ".";
    }
    printf "]\n\n";
    
    printf "%sTotal Docker Limit:       %6.2f GiB%s\n", LIM_COLOR, l_gb, NC;
    printf "%sTotal Docker Reserve:     %6.2f GiB%s\n", RES_C, r_gb, NC;
    
    margin = h_gb - l_gb;
    printf (margin < m_gb ? RED : "") "Host OS Headroom:         %6.2f GiB" NC "\n", margin;
    print "================================================================";

    printf "\n%-34s %-15s %-15s\n", "App Folder", "Limit", "Res";
    print "----------------------------------------------------------------";
    for (a in all_apps) {
        r_str = (app_res[a] > 0 ? human(app_res[a]) : "0 MiB");
        if (app_limit[a] > 0) {
            printf "%-34s %-15s %-15s\n", a, human(app_limit[a]), r_str;
        } else {
            printf "%-34s %s%-15s%s %-15s\n", a, RED, "Unlimited", NC, r_str;
        }
    }

    print "\n================= Detailed Container Breakdown =================\n";
    for (a in all_apps) {
        printf "[%s]\n", a;
        l_line = ""; r_line = "";
        found_any = 0;

        for (key in all_services) {
            split(key, parts, SUBSEP);
            if (parts[1] == a) {
                s = parts[2];
                lim = (service_limit[a, s] != "" ? service_limit[a, s] : RED "Unlimited" NC);
                l_line = (l_line == "" ? s " (" lim ")" : l_line " + " s " (" lim ")");
                if (service_res[a, s] != "") {
                    r_line = (r_line == "" ? s " (" service_res[a, s] ")" : r_line " + " s " (" service_res[a, s] ")");
                }
                found_any = 1;
            }
        }
        
        if (found_any) {
            printf "  ├── Limits:       %s\n", l_line;
            if (r_line != "") printf "  └── Reservations: %s\n", r_line;
        }
        print "";
    }
}'
