#!/bin/bash

docker compose -f ./compose-setup.yaml up -d nginx
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "cloud.duvanoff.su" -d "www.cloud.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "office.duvanoff.su" -d "www.office.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "duvanoff.su" -d "www.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml down nginx

docker compose -f ./compose.yaml up -d

docker compose -f ./compose-setup.yaml run --rm php-config