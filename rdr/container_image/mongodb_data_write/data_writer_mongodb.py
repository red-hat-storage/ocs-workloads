import pymongo
import time
import string
import logging
import socket
import secrets
from datetime import datetime
from faker import Faker
import random
import os

logging.basicConfig(
    format="%(asctime)s - %(threadName)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

DB_USER = os.environ.get("MONGO_DB_USER")
DB_PASSWORD = os.environ.get("MONGO_DB_PASSWORD")
DB_HOST = os.environ.get("MONGO_DB_HOST")
DB_PORT = os.environ.get("MONGO_DB_PORT")
MONGO_URI = f"mongodb://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/"
DB_NAME = "mycollection"
MONGO_COLLECTION_NAME = "mycollection"
fake = Faker()
client = pymongo.MongoClient(MONGO_URI)


def create_db():
    try:
        # Connect to MongoDB

        # Check if the database already exists
        existing_databases = client.list_database_names()
        if DB_NAME in existing_databases:
            logging.info(f"Database '{DB_NAME}' already exists.")
        else:
            # Create a new database
            var = client[DB_NAME]
            logging.info(f"Database '{DB_NAME}' '{var}' created successfully.")

    except pymongo.errors.ConnectionError as e:
        logging.info(f"Error connecting to MongoDB: {e}")
    except Exception as e:
        logging.info(f"An error occurred: {e}")


def generate_random_data():
    data = {
        "date_time": str(datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")),
        "res": "".join(
            secrets.choice(string.ascii_uppercase + string.digits) for i in range(10)
        ),
        "host": socket.gethostname(),
        "first_name": fake.first_name(),
        "last_name": fake.last_name(),
        "email": fake.email(),
        "zipcode": fake.postcode(),
        "city": fake.city(),
        "country": fake.country(),
        "address": fake.address(),
        "latitude": str(fake.latitude()),
        "longitude": str(fake.longitude()),
    }
    return data


# Insert random data into MongoDB
def insert_random_data():
    for x in range(0, 5):
        data = generate_random_data()
        collection.insert_one(data)
        logging.info(f"Inserted data: {data}")
        time.sleep(5)
    logging.info('\n')


# Read random data from MongoDB
def read_random_data():
    data_count = collection.count_documents({})
    index_value = None
    if data_count >= 30:
        index_value = random.randrange(10, 30, 3)
    if index_value:
        data_db = list(collection.find())
        random.shuffle(data_db)
        for random_doc in data_db[:index_value]:
            logging.info(f"Read data: {random_doc}")
    else:
        random_doc = collection.find_one()
        logging.info(f"Read data: {random_doc}")
    logging.info('\n')


if __name__ == "__main__":

    create_db()
    db = client[MONGO_COLLECTION_NAME]
    collection = db[DB_NAME]
    while True:
        insert_random_data()

        # Read random data from MongoDB
        read_random_data()

    # Close the MongoDB connection
    client.close()
