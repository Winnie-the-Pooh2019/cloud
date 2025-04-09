#!/bin/bash

volumes=( \
"db-data" \
"cloud-data" \
)

for volume in "${volumes[@]}"; do
  echo "Restoring volume: $volume"

  docker compose -f ./compose-setup.yaml run --build \
  -v "cloud_$volume":/tmp/dist \
  -v $(pwd)/backup/"$volume"/:/tmp/back --rm backup -a check
done