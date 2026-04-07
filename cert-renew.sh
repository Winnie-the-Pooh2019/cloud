#!/bin/bash

docker compose -f "$1"/compose.yaml stop

docker compose -f "$1"/compose-setup.yaml up -d nginx-setup

docker compose -f "$1"/compose-setup.yaml run --rm certbot renew
docker compose -f "$1"/compose-setup.yaml down nginx-setup

docker compose -f "$1"/compose.yaml start
