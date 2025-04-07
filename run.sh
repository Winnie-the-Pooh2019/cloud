docker compose -f ./compose-setup.yaml run --build \
-v $(pwd)/volumes/source:/tmp/dist \
-v $(pwd)/volumes/backup/:/tmp/back \
backup \
-a check