FROM python:3.11-alpine
RUN apk add --no-cache bash
RUN pip install --no-cache-dir pymongo Faker
RUN  mkdir /script
COPY data_writer_mongodb.py /script/db.py
