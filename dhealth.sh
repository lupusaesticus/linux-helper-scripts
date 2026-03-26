#!/bin/bash
# A utility to monitor drive health and age using smartctl and nvme-cli.
# Supports formatted tables, machine-readable logs, and specific metric extraction.
# Generated with the help of Gemini by Lupus (https://github.com/lupusaesticus/linux-helper-scripts)

# --- Setup & Defaults ---
output_file=${DHEALTH_OUT:-""}
mode="machine"
target_dev=""
red='\033[0;31m'
reset='\033[0m'

# --- Help Text ---
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -t, --table       Output a human-readable, colorized table.
  -m, --machine     Output pipe-delimited data (Default).
  -d, --drive DEV   Get specific metric for a drive (Health% for SSD, Age for HDD).
  -l, --list        List available devices using: lsblk -dno NAME,MODEL,SIZE
  -o, --output FILE Save the report to a specific file.
  -h, --help        Show this help message.

EOF
    exit 0
}

# --- Parse Flags ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--table)   mode="table"; shift ;;
        -m|--machine) mode="machine"; shift ;;
        -d|--drive)   target_dev="$2"; shift 2 ;;
        -l|--list)    
            echo "Available Devices (via lsblk -dno NAME,MODEL,SIZE):"
            lsblk -dno NAME,MODEL,SIZE | awk '{printf "  %-10s %-20s %s\n", $1, $2, $3}'
            exit 0 ;;
        -o|--output)  output_file="$2"; shift 2 ;;
        -h|--help)    show_help ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
done

# --- Core Logic: Single Metric Extraction ---
get_metrics() {
    local dev=$1
    local rota=$(lsblk -dno ROTA "/dev/$dev")
    local model_raw=$(lsblk -dno MODEL "/dev/$dev")
    local model=$(echo "$model_raw" | awk '{print $1}')
    local label=$(lsblk -no LABEL "/dev/$dev" | grep . | head -1)
    local name=$([[ -z "$label" ]] && echo "n/a" || echo "$label")
    
    local life="n/a" hours_num="" age_display="n/a"

    if [[ "$dev" == nvme* ]]; then
        local smart=$(sudo nvme smart-log "/dev/$dev" 2>/dev/null)
        local used=$(echo "$smart" | grep percentage_used | awk '{print $3}' | tr -dc '0-9')
        [[ -n "$used" ]] && life="$((100 - used))%"
        hours_num=$(echo "$smart" | grep power_on_hours | awk '{print $3}' | tr -dc '0-9')
    else
        local smart_data=$(sudo smartctl -A "/dev/$dev" 2>/dev/null)
        [[ ! "$smart_data" =~ "Power_On_Hours" ]] && smart_data=$(sudo smartctl -d sat -A "/dev/$dev" 2>/dev/null)
        
        if [[ "$rota" == "0" || "${model_raw,,}" == *"ssd"* ]]; then
            # SSD Health IDs
            local life_val=$(echo "$smart_data" | awk '$1=="232"||$1=="231"||$1=="233"||$1=="169"||$1=="202" {v=$4; if(v>100||v==0)v=$10; print v}' | head -1 | tr -dc '0-9')
            if [[ -n "$life_val" ]]; then
                life="${life_val}%"
            else
                life="100%"
            fi
        else
            # HDD Logic
            life=$(echo "$smart_data" | awk '$1=="5"||$1=="197" {sum+=$10} END {print (sum==""?"0":sum" err")}')
        fi
        # Handle SanDisk "70358h+00m..." vs raw "70358"
        hours_num=$(echo "$smart_data" | awk '$1=="9" {print $10}' | sed 's/h.*//' | tr -dc '0-9')
    fi

    # Age Calculation & Sanity Check (Max 15 years/131400 hours)
    if [[ -n "$hours_num" && "$hours_num" -gt 0 && "$hours_num" -le 131400 ]]; then
        if [[ "$hours_num" -lt 8760 ]]; then
            age_display="$((hours_num / 24))d"
        else
            local years=$((hours_num / 8760))
            local remain=$((hours_num % 8760))
            local months=$((remain / 730))
            age_display="${years}y ${months}m"
        fi
    else
        hours_num="n/a"
    fi

    echo "$name|$dev|$life|$hours_num|$age_display|$model"
}

# --- Execution ---

if [[ -n "$target_dev" ]]; then
    target_dev_name="${target_dev#/dev/}"
    res=$(get_metrics "$target_dev_name")
    IFS='|' read -r name dev life raw_hrs age model <<< "$res"
    
    rota=$(lsblk -dno ROTA "/dev/$target_dev_name")
    model_name=$(lsblk -dno MODEL "/dev/$target_dev_name")

    if [[ "$dev" == nvme* || "$rota" == "0" || "${model_name,,}" == *"ssd"* ]]; then
        echo "$life"
    else
        echo "$age"
    fi
    exit 0
fi

report_out=""
if [[ "$mode" == "table" ]]; then
    report_out+="LABEL                | DEVICE          | HEALTH  | HOURS   | AGE      | MODEL\n"
    report_out+="----------------------------------------------------------------------------------\n"
else
    report_out+="#LABEL|DEVICE|HEALTH|HOURS|AGE|MODEL\n"
fi

for d in $(lsblk -dno NAME,TYPE | grep disk | awk '{print $1}'); do
    res=$(get_metrics "$d")
    IFS='|' read -r name dev life raw_hrs age model <<< "$res"
    
    if [[ "$mode" == "table" ]]; then
        l_col="" && [[ "${life%%%*}" -le 50 && "$life" == *% ]] && l_col="$red"
        h_col="" && [[ "$raw_hrs" != "n/a" && "$raw_hrs" -gt 50000 ]] && h_col="$red"
        
        line=$(printf "%-20s | %-15s | %b%-7s%b | %-7s | %b%-8s%b | %s" \
            "$name" "$dev" "$l_col" "$life" "$reset" "$raw_hrs" "$h_col" "$age" "$reset" "$model")
        report_out+="$line\n"
    else
        report_out+="$name|$dev|$life|$raw_hrs|$age|$model\n"
    fi
done

if [[ -n "$output_file" ]]; then
    echo -ne "$report_out" > "$output_file"
else
    echo -ne "$report_out"
fi