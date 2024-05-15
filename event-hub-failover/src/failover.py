import os
import logging
import time
from azure.eventhub import EventHubProducerClient, EventData, EventDataBatch
from azure.eventhub.exceptions import EventHubError

# Environment variables for Event Hub connection strings
PRIMARY_CONNECTION_STRING = os.getenv('PRIMARY_EVENT_HUB_CONNECTION_STRING')
SECONDARY_CONNECTION_STRING = os.getenv('SECONDARY_EVENT_HUB_CONNECTION_STRING')
EVENT_HUB_NAME = os.getenv('EVENT_HUB_NAME')

# Constants for retry logic
MAX_RETRIES = 3
RETRY_DELAY = 5  # seconds

def send_event_data(producer_client, event_data_batch):
    try:
        producer_client.send_batch(event_data_batch)
        logging.info('Event data sent successfully.')
    except EventHubError as e:
        logging.error(f'Failed to send event data: {e}')
        raise

def create_producer_client(connection_string):
    return EventHubProducerClient.from_connection_string(
        connection_string,
        eventhub_name=EVENT_HUB_NAME
    )

def main():
    logging.basicConfig(level=logging.INFO)
    
    producer_client = create_producer_client(PRIMARY_CONNECTION_STRING)
    event_data_batch = producer_client.create_batch()
    event_data_batch.add(EventData("Sample event data"))

    for attempt in range(MAX_RETRIES):
        try:
            logging.info('Attempting to send event data to primary Event Hub...')
            with producer_client:
                send_event_data(producer_client, event_data_batch)
            break  # Exit loop if successful
        except Exception as primary_error:
            logging.error(f'Primary Event Hub attempt {attempt + 1} failed: {primary_error}')
            if attempt < MAX_RETRIES - 1:
                logging.info(f'Retrying in {RETRY_DELAY} seconds...')
                time.sleep(RETRY_DELAY)
            else:
                logging.info('All primary attempts failed, switching to secondary Event Hub...')
                try:
                    producer_client = create_producer_client(SECONDARY_CONNECTION_STRING)
                    event_data_batch = producer_client.create_batch()
                    event_data_batch.add(EventData("Sample event data"))
                    with producer_client:
                        send_event_data(producer_client, event_data_batch)
                    break  # Exit loop if successful
                except Exception as secondary_error:
                    logging.error(f'Secondary Event Hub attempt failed: {secondary_error}')
                    if attempt < MAX_RETRIES - 1:
                        logging.info(f'Retrying in {RETRY_DELAY} seconds...')
                        time.sleep(RETRY_DELAY)
                    else:
                        logging.critical('All retry attempts failed. Exiting.')
                        raise

if __name__ == "__main__":
    main()
