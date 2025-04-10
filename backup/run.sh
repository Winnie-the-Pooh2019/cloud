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
if [ -z "$DESTINATION" ] || [ -z "$BACKUP" ]; then
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

echo "$(find "$BACKUP" -type d)"
echo "$(find "$DESTINATION" -type d)"


DEST_DIRS=($(find "$DESTINATION" -mindepth 1 -maxdepth 1 -type d))

for dest_dir in "${DEST_DIRS[@]}"; do
    folder_name=$(basename "$dest_dir")
    backup_dir="$BACKUP/$folder_name"

    echo "Backing up '$dest_dir' to '$backup_dir'..."
    if [ -z "$COMMAND" ]; then
        python3 ./main.py -d "$dest_dir" -b "$backup_dir"
    else
        python3 ./main.py -d "$dest_dir" -b "$backup_dir" -a $COMMAND
    fi

done
