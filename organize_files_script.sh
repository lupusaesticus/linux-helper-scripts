#!/bin/bash

# Script to move each file in current directory into its own subfolder
# The subfolder name will be the filename without extension

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -n, --dry-run  Show what would be done without actually doing it"
    echo "  -v, --verbose  Show detailed output"
}

# Default options
DRY_RUN=false
VERBOSE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Counter for processed files
count=0

# Process each file in current directory
for file in *; do
    # Skip if it's a directory
    if [[ -d "$file" ]]; then
        continue
    fi
    
    # Skip if it's the script itself (only if script is in current directory)
    if [[ "$file" == "$(basename "$0")" ]] && [[ "$(dirname "$0")" == "." || "$(dirname "$0")" == "$(pwd)" ]]; then
        continue
    fi
    
    # Skip hidden files (starting with .)
    if [[ "$file" == .* ]]; then
        continue
    fi
    
    # Get filename without extension
    filename_no_ext="${file%.*}"
    
    # Skip if filename would be empty after removing extension
    if [[ -z "$filename_no_ext" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo "Skipping '$file' - no base name after removing extension"
        fi
        continue
    fi
    
    # Create directory name (same as filename without extension)
    dir_name="$filename_no_ext"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would create directory '$dir_name' and move '$file' into it"
    else
        # Create the directory if it doesn't exist
        if [[ ! -d "$dir_name" ]]; then
            mkdir -p "$dir_name"
            if [[ "$VERBOSE" == true ]]; then
                echo "Created directory: $dir_name"
            fi
        fi
        
        # Move the file into the directory
        mv "$file" "$dir_name/"
        
        if [[ "$VERBOSE" == true ]]; then
            echo "Moved '$file' -> '$dir_name/$file'"
        fi
    fi
    
    ((count++))
done

# Summary
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run completed. $count files would be processed."
else
    echo "Completed! Processed $count files."
fi
