import ccxt
import mysql.connector
import time
from credentials import cnx as credentials_cnx
from datetime import datetime

# Map timeframes to seconds
timeframe_to_seconds = {
    '1m': 60,
    '5m': 300,
    '15m': 900,
    '1h': 3600,
    '6h': 21600,
    '1d': 86400,
    '1w': 604800
}

# Function to connect to MySQL with retry logic
def connect_to_mysql():
    try:
        if not credentials_cnx.is_connected():
            credentials_cnx.reconnect(attempts=3, delay=3)
        if credentials_cnx.is_connected():
            print("Connected to MySQL.")
            return credentials_cnx
        else:
            print("Failed to reconnect to MySQL.")
            return None
    except mysql.connector.Error as err:
        print(f"Error connecting to MySQL: {err}")
        time.sleep(10)
        return None

# Function to create table with the required schema
def create_table(pair, timeframe):
    table_name = f'`coinbase_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    if cnx:
        cursor = cnx.cursor()
        cursor.execute(f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                time DATETIME,
                open FLOAT,
                high FLOAT,
                low FLOAT,
                close FLOAT,
                volume FLOAT
            );
        """)
        cnx.commit()
        cursor.close()  # Avoid closing the main connection

# Function to fetch candle data from Coinbase
def get_candles(pair, numcandles, timeframe, exchange):
    granularity = timeframe_to_seconds[timeframe]
    return exchange.fetch_ohlcv(pair.replace("_", "/"), timeframe=granularity, limit=numcandles)

# Retry mechanism for fetching candles with IP ban/rate-limit handling
def get_candles_with_retry(pair, numcandles, timeframe, exchange, retries=3, delay=1):
    attempt = 0
    while attempt < retries:
        try:
            candles = get_candles(pair, numcandles, timeframe, exchange=exchange)
            if candles:
                return candles
        except Exception as e:
            error_message = str(e).lower()
            print(f"Error fetching candles: {e}")
            if "ban" in error_message or "403" in error_message or "rate limit" in error_message:
                print("IP might be banned or rate-limited.")
                break
        attempt += 1
        print(f"Retrying... ({attempt}/{retries})")
        time.sleep(delay)
    return None

from datetime import datetime

def insert_candles(data, pair, timeframe):
    table_name = f'`coinbase_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    if cnx:
        cursor = cnx.cursor()

        # Select rows to delete and delete them in a separate step
        delete_query = f"""
            DELETE FROM {table_name} 
            WHERE `id` IN (
                SELECT `id` FROM (
                    SELECT `id` FROM {table_name} 
                    ORDER BY `id` DESC LIMIT 1 OFFSET 299
                ) AS temp_table
            )
        """
        cursor.execute(delete_query)

        # Insert new candle data with correct timestamp formatting
        for candle in data:
            # Convert timestamp in milliseconds to MySQL-compatible DATETIME format
            time_formatted = datetime.utcfromtimestamp(candle[0] / 1000).strftime('%Y-%m-%d %H:%M:%S')
            cursor.execute(f"""
                INSERT INTO {table_name} (time, open, high, low, close, volume)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (time_formatted, candle[1], candle[2], candle[3], candle[4], candle[5]))

        cnx.commit()
        cursor.close()
        print(f"Inserted {len(data)} candles for {pair} at {timeframe}.")

# Main function to iterate over pairs and timeframes
def main():
    # Initialize exchange and pairs
    exchange = ccxt.coinbasepro()
    pairs = ['BTC-USD', 'ETH-USD', 'POL-USD', 'ARB-USD', 'VELO-USD', 'AERO-USD', 'LINK-USD']
    timeframes = ['6h']  # Assuming you want only one timeframe for all pairs

    for pair in pairs:
        for timeframe in timeframes:
            table_name = f'coinbase_{pair}_{timeframe}'
            create_table(pair, timeframe)

            # Fetch candles with retry mechanism
            candles = get_candles_with_retry(pair, 300, timeframe, exchange)

            # Insert candles if data was fetched successfully
            if candles:
                insert_candles(candles, pair, timeframe)
            time.sleep(1)  # Wait 1 second between each request to avoid rate limits

if __name__ == "__main__":
    main()

