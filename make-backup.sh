#!/bin/bash

volumes=( \
"db-data" \
"cloud-data" \
"db-office-data" \
"office-data" \
"office-log" \
"office-public" \
"office-fonts" \
"track-data" \
"track-logs" \
)

for volume in "${volumes[@]}"; do
  echo "Creating a backup of volume cloud_$volume"

  mkdir -p $(pwd)/backup/"$volume"

  docker compose -f ./compose-setup.yaml run --build \
  -v "cloud_$volume":/tmp/dist \
  -v $(pwd)/backup/"$volume"/:/tmp/back --rm backup -a backup
done