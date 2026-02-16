from credentials import cnx as credentials_cnx
import datetime
import time
import requests
import mysql.connector
import redis
from datetime import datetime

def connect_to_mysql():
    try:
        if credentials_cnx.is_connected():
            return credentials_cnx
        else:
            credentials_cnx.reconnect(attempts=3, delay=3)
            if credentials_cnx.is_connected():
                print("Reconnected to MySQL.")
                return credentials_cnx
            else:
                print("Failed to reconnect to MySQL.")
                return None
    except mysql.connector.Error as err:
        print(f"Error connecting to MySQL: {err}")
        time.sleep(10)
        return None



def connect_to_redis():
    try:
        r = redis.Redis(host='localhost', port=6379, db=0)  # Local Redis server
        print("Connected to Redis")
        return r
    except redis.RedisError as err:
        print(f"Error connecting to Redis: {err}")
        return None

timeframe_to_seconds = {
    '1m': 60,
    '5m': 300,
    '15m': 900,
    '1h': 3600,
    '6h': 21600,
    '1d': 86400,
    '1w': 604800
}

# Function to create table with the required schema
def create_table(exchange,pair, timeframe):
    table_name = f'`{exchange}_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    if cnx:
        cursor = cnx.cursor()
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                `id` INT PRIMARY KEY,
                time BIGINT,
                open FLOAT,
                high FLOAT,
                low FLOAT,
                close FLOAT,
                volume FLOAT
            );
        """)
        cnx.commit()
        cursor.close()
        cnx.close()

def get_candles(exchange,pair, numcandles, timeframe):
    product_id = pair.replace("_", "-")  # Convert pair to the required format, e.g., BTC-USD
    granularity = timeframe_to_seconds.get(timeframe)  # Convert timeframe to seconds
    
    if granularity is None:
        print(f"Error: Granularity for timeframe '{timeframe}' is not defined.")
        return None

    url = f"https://api.exchange.coinbase.com/products/{product_id}/candles"
    params = {
        'granularity': granularity
    }

    # Request data from the public endpoint
    try:
        response = requests.get(url, params=params)
        response.raise_for_status()  # Raise an error for HTTP codes 4xx/5xx

        candles = response.json()
        # Return only the last `numcandles` if available
        return candles[:numcandles] if len(candles) > numcandles else candles

    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP error occurred: {http_err} - {response.text}")
    except requests.exceptions.RequestException as req_err:
        print(f"Request error occurred: {req_err}")
    except ValueError as parse_err:
        print(f"Error parsing JSON: {parse_err}")
    except Exception as e:
        print(f"Unexpected error fetching candles: {e}")

    return None

def get_candles_with_retry(pair, numcandles, timeframe, exchange, retries=1, delay=1):
    attempt = 0
    while attempt < retries:
        try:
            candles = get_candles(exchange,pair, numcandles, timeframe)
            if candles is not None:
                return candles
        except Exception as e:
            error_message = str(e).lower()
            print(f"Error fetching candles: {e}")
            # Check if the error message indicates an IP ban
            if "ban" in error_message or "403" in error_message or "rate limit" in error_message:
                print("It looks like your IP might be banned or rate-limited.")
                break  # Optionally exit the loop if the IP is banned
        attempt += 1
        print(f"Retrying... ({attempt}/{retries})")
        time.sleep(delay)
    return None

# Function to insert candle data into MySQL and truncate table to 300 rows
def store_last_close_in_redis(redis_client, key, last_close):
    try:
        redis_client.set(key, last_close)
        print(f"Stored {key} last close: {last_close} in Redis")
    except redis.RedisError as err:
        print(f"Error storing {key} last close in Redis: {err}")

def insert_candles(exchange, data, pair, timeframe,numcandles,redis_client):
    table_name = f'`{exchange}_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    data = sorted(data, key=lambda x: x[0])
    if cnx:
        cursor = cnx.cursor()
        try:
            # Update existing candle data by `id`
            for i, candle in enumerate(data, start=1):
                timestamp = candle[0]
                #cursor.execute(f"""
                #   UPDATE {table_name}
                #   SET time = %s, open = %s, high = %s, low = %s, close = %s, volume = %s
                #   WHERE id = %s
                #""", (timestamp, candle[1], candle[2], candle[3], candle[4], candle[5],numcandles - i+ 1))
                timestamp = candle[0]
                candle_id = numcandles - i + 1  # This is your primary key

                cursor.execute(f"""
                    INSERT INTO {table_name} (id, time, open, high, low, close, volume)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                    time = VALUES(time),
                    open = VALUES(open),
                    high = VALUES(high),
                    low = VALUES(low),
                    close = VALUES(close),
                    volume = VALUES(volume)
                    """, (candle_id, timestamp, candle[1], candle[2], candle[3], candle[4], candle[5]))

            cnx.commit()
            last_close = data[-1][4]
            if last_close is not None:
                redis_key = f"{exchange}_{pair}"
                store_last_close_in_redis(redis_client, redis_key, last_close)

            print(f"Inserted {len(data)} candles for {pair} at {timeframe} (table name: {table_name}).")

        except mysql.connector.Error as err:
            print(f"Error updating candles for {pair} at {timeframe}: {err}")
            cnx.rollback()  # Roll back any changes if an error occurs

        finally:
            cursor.close()  # Ensure the cursor is closed regardless of success or error

# Main function to iterate over pairs and timeframes
def main():
    # Initialize exchange and pairs
    pairs = ['OP-USD','SNX-USD','MORPHO-USD','BTC-USD', 'ETH-USD','POL-USD','ARB-USD','VELO-USD','AERO-USD','LINK-USD','SOL-USD','ETH-USD','BTC-USD','VELO-USD']  # Add more pairs as needed
    timeframes = ['6h','6h','6h','6h', '6h', '6h', '6h', '15m', '6h', '6h','6h','1d','1d','1d']
    exchange = 'coinbase'
    numcandles = 300
    redis_client = connect_to_redis()
    for pair, timeframe in zip(pairs, timeframes):
            table_name = f'{exchange}_{pair}_{timeframe}'
            create_table(exchange,pair, timeframe)

            # Fetch candles with retry mechanism
            candles = get_candles_with_retry(exchange=exchange,pair=pair,numcandles=numcandles,timeframe=timeframe)

            # Insert candles if data was fetched successfully
            if candles:
                print(f"Inserting candles on MYSQL for {exchange} {pair} {timeframe}") 
                insert_candles(exchange,candles, pair, timeframe,numcandles,redis_client)
            time.sleep(1)  # Wait 1 second between each request to avoid rate limits

if __name__ == "__main__":
    main()
