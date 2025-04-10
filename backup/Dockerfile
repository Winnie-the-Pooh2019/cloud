FROM ubuntu/python

WORKDIR /
COPY . .

ENTRYPOINT ["python", "main.py", "-d", "/tmp/dist", "-b", "/tmp/back"]