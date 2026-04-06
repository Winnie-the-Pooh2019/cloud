#!/bin/bash

echo "Stopping containers"
docker compose -f ./compose.yaml stop
docker compose -f ./docmost.yaml stop
docker compose -f ./taigaio.yaml stop

echo "Setting up certificates"
docker compose -f ./compose-setup.yaml up -d nginx-setup
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "cloud.duvanoff.su" -d "www.cloud.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "office.duvanoff.su" -d "www.office.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "taiga.duvanoff.su" -d "www.taiga.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "doc.duvanoff.su" -d "www.doc.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "out.doc.duvanoff.su" -d "www.out.doc.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email --non-interactive --keep-until-expiring -d "duvanoff.su" -d "www.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml down nginx-setup

echo "Initialize services"
docker compose -f ./compose-setup.yaml run --rm php-config

echo "Run services"
#docker compose -f ./taigaio.yaml up -d
docker compose -f ./docmost.yaml up -d
docker compose -f ./outline.yaml up -d
docker compose -f ./compose.yaml up -d

curdir=$(pwd)

echo "adding tasks to cron"
echo "0 9 * * 1 $curdir/cert-renew.sh $curdir >> /var/log/renew-ssl.log" > ./cron-file

crontab ./cron-file
rm ./cron-file