#!/bin/bash

# Load local environment variables if the file exists
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

# set output file (defaults working dir, which will be / if running as root)
output_file=${DHEALTH_OUT:-$PWD/drivehealth.txt}

# outputs info on all mounted drives
# must be run as root / added to sudo crontab to work properly

# Add the header with a # so awk/conky can skip it if needed
echo "#LABEL|DEVICE|HEALTH|AGE|MODEL" > "$output_file"

for d in $(lsblk -dno NAME,ROTA,TYPE | grep disk | awk '{print $1":"$2}'); do
    dev="${d%:*}"
    rota="${d#*:}"
    label=$(lsblk -no LABEL /dev/"$dev" | grep . | head -1)
    name=$([[ -z "$label" ]] && echo "n/a" || echo "$label")
    model=$(lsblk -dno MODEL /dev/"$dev" | awk '{print $1}')
    
    hours_num=""
    life="n/a"

    # 1. Extraction (Using the original fixed logic)
    if [[ "$dev" == nvme* ]]; then
        life_num=$(sudo nvme smart-log /dev/"$dev" 2>/dev/null | grep percentage_used | awk '{print 100-$3}')
        [[ -n "$life_num" ]] && life="${life_num}%"
        hours_num=$(sudo nvme smart-log /dev/"$dev" 2>/dev/null | grep power_on_hours | awk '{print $3}' | tr -dc '0-9')
    else
        smart_data=$(sudo smartctl -A /dev/"$dev" 2>/dev/null)
        [[ ! "$smart_data" =~ "Power_On_Hours" ]] && smart_data=$(sudo smartctl -d sat -A /dev/"$dev" 2>/dev/null)
        
        if [[ "$rota" == "0" ]]; then
            life_num=$(echo "$smart_data" | awk '$1=="231"||$1=="233"||$1=="232"||$1=="169" {v=$4; if(v>100||v==0)v=$10; print v}' | head -1 | tr -dc '0-9')
            [[ -n "$life_num" ]] && life="${life_num}%"
        else
            life=$(echo "$smart_data" | awk '$1=="5"||$1=="197" {sum+=$10} END {print (sum==""?"0":sum" err")}')
        fi
        hours_num=$(echo "$smart_data" | awk '$1=="9" {print $10}' | tr -dc '0-9')
    fi

    # 2. Sanity Check (The "80,000 year" Shield)
    # 131400 hours = 15 years. If it's higher than that, the data is corrupt.
    if [[ -z "$hours_num" || "$hours_num" -eq 0 || "$hours_num" -gt 131400 ]]; then
        age_display="n/a"
    elif [[ "$hours_num" -lt 8760 ]]; then
        age_display="$((hours_num / 24))d"
    else
        # Force scale=1 for clean decimal and catch any bc errors
        age_val=$(echo "scale=1; $hours_num / 8760" | bc 2>/dev/null)
        age_display="${age_val}y"
    fi

    # 3. Write to file
    echo "$name|$dev|$life|$age_display|$model" >> "$output_file"
done
