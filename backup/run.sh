#!/bin/bash

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -b|--backup)
            BACKUP="$2"
            shift 2
            ;;
        -c|--command)
            COMMAND="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Check required arguments
if [ -z "$DESTINATION" ] || [ -z "$BACKUP" || -z "$COMMAND" ]; then
    echo "Usage: $0 -d <destination_folder> -b <backup_folder> -c <command>"
    exit 1
fi

# Check if folders exist
if [ ! -d "$DESTINATION" ]; then
    echo "Destination folder does not exist: $DESTINATION"
    exit 1
fi

if [ ! -d "$BACKUP" ]; then
    echo "Backup folder does not exist: $BACKUP"
    exit 1
fi

# Loop through backup directories
find "$BACKUP" -type d | while read -r bpath; do
    # Strip base backup path
    relpath="${bpath#$BACKUP/}"
    dpath="$DESTINATION/$relpath"

    # Skip if it's the root backup dir itself
    [ "$relpath" = "$bpath" ] && continue

    # Check if corresponding destination folder exists
    if [ -d "$dpath" ]; then
        echo "-d $dpath -b $bpath"
        python3 ./main.py -d "$dpath" -b "$bpath" -c "$COMMAND"
    fi
done
