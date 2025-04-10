FROM python:3.8-slim

WORKDIR /
COPY . .

ENTRYPOINT ["bash", "./run.sh", "-d", "/dist", "-b", "/backup"]