FROM python:3.11-alpine
RUN apk add --no-cache bash
RUN pip install --no-cache-dir mysql-connector-python Faker
RUN  mkdir /script
COPY data_writer_mysql.py /script/db.py
