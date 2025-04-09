#!/bin/bash

volumes=( \
"db-data" \
"cloud-data" \
"db-office-data" \
"office-data" \
"office-public" \
"office-fonts" \
"track-data" \
)

for volume in "${volumes[@]}"; do
  echo "Restoring volume: $volume"

  docker compose -f ./compose-setup.yaml run --build \
  -v "cloud_$volume":/tmp/dist \
  -v $(pwd)/backup/"$volume"/:/tmp/back --rm backup -a check

  docker run --rm -v "cloud_$volume":/volume alpine chmod -R 770 /volume

done

docker compose -f ./compose-setup.yaml up -d nginx
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "cloud.duvanoff.su" -d "www.cloud.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "office.duvanoff.su" -d "www.office.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "track.duvanoff.su" -d "www.track.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "ivan.duvanov.3@gmail.com" --agree-tos --no-eff-email -d "duvanoff.su" -d "www.duvanoff.su" --preferred-challenges http
docker compose -f ./compose-setup.yaml down nginx

docker compose -f ./compose.yaml up -d

docker compose -f ./compose-setup.yaml run --rm php-config

curdir=$(pwd)

# renewing certificates
echo "0 9 * * 1 /usr/bin/docker compose -f $curdir/compose-setup.yaml run --rm certbot renew >> /var/log/renew-ssl.log && /usr/bin/docker compose -f $(pwd)/compose.yaml kill -s SIGHUP nginx" > ./cron

# adding autobackup to crontab
for volume in "${volumes[@]}"; do
  echo "adding autobackup of volume cloud_$volume to crontab"

  echo "30 7 * * * /usr/bin/docker compose -f $curdir/compose-setup.yaml run -v cloud_$volume:/tmp/dist -v $curdir/backup/$volume/:/tmp/back --rm backup -a check >> /var/log/backup.log" >> ./cron
done

crontab ./cron