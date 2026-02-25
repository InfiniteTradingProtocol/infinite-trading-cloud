from credentials import get_connection
import datetime
import time
import requests
import mysql.connector
import redis
from datetime import datetime

def connect_to_mysql():
    """Get a fresh connection from the pool"""
    try:
        return get_connection()
    except mysql.connector.Error as err:
        print(f"Error getting connection from pool: {err}")
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
        try:
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
        finally:
            cnx.close()

def get_last_candle_time(exchange, pair, timeframe):
    """Get the timestamp of the most recent candle in MySQL"""
    table_name = f'`{exchange}_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    if cnx:
        try:
            cursor = cnx.cursor()
            cursor.execute(f"SELECT MAX(time) FROM {table_name}")
            result = cursor.fetchone()
            cursor.close()
            if result and result[0]:
                # Check if it's already an int/timestamp or datetime object
                if isinstance(result[0], int):
                    return result[0]
                else:
                    return int(result[0].timestamp())  # Convert datetime to Unix timestamp
        except mysql.connector.Error as err:
            # Table might not exist yet
            pass
        finally:
            cnx.close()
    return None

def get_candle_count(exchange, pair, timeframe):
    """Get the number of candles currently in MySQL"""
    table_name = f'`{exchange}_{pair}_{timeframe}`'
    cnx = connect_to_mysql()
    if cnx:
        try:
            cursor = cnx.cursor()
            cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
            result = cursor.fetchone()
            cursor.close()
            return result[0] if result else 0
        except mysql.connector.Error as err:
            pass
        finally:
            cnx.close()
    return 0

def get_candles(exchange, pair, numcandles, timeframe, start_time=None, end_time=None):
    """Fetch candles from Coinbase API with optional time range"""
    product_id = pair.replace("_", "-")
    granularity = timeframe_to_seconds.get(timeframe)
    
    if granularity is None:
        print(f"Error: Granularity for timeframe '{timeframe}' is not defined.")
        return None

    url = f"https://api.exchange.coinbase.com/products/{product_id}/candles"
    params = {'granularity': granularity}
    
    # Add time range if specified
    if start_time:
        params['start'] = start_time
    if end_time:
        params['end'] = end_time

    try:
        response = requests.get(url, params=params)
        response.raise_for_status()

        candles = response.json()
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

def get_candles_with_retry(pair, numcandles, timeframe, exchange, retries=1, delay=1, start_time=None, end_time=None):
    attempt = 0
    while attempt < retries:
        try:
            candles = get_candles(exchange, pair, numcandles, timeframe, start_time, end_time)
            if candles is not None:
                return candles
        except Exception as e:
            error_message = str(e).lower()
            print(f"Error fetching candles: {e}")
            if "ban" in error_message or "403" in error_message or "rate limit" in error_message:
                print("It looks like your IP might be banned or rate-limited.")
                break
        attempt += 1
        print(f"Retrying... ({attempt}/{retries})")
        time.sleep(delay)
    return None

def backfill_missing_candles(exchange, pair, timeframe, numcandles, redis_client, max_candles=300):
    """Detect gaps and backfill missing candles on initialization - handles 300+ candle gaps"""
    current_count = get_candle_count(exchange, pair, timeframe)
    
    if current_count >= max_candles:
        # Database is full, just fetch the last 2 candles to update
        print(f"[{pair}_{timeframe}] Database full ({current_count} candles), fetching last 2 for update")
        candles = get_candles_with_retry(pair=pair, numcandles=2, timeframe=timeframe, exchange=exchange)
        if candles:
            insert_candles(exchange, candles, pair, timeframe, numcandles, redis_client)
        return
    
    # Need to backfill - iteratively fetch in 300-candle batches
    missing = max_candles - current_count
    print(f"[{pair}_{timeframe}] Found {current_count} candles, need {missing} more to reach {max_candles}")
    
    max_iterations = 10  # Safety limit to prevent infinite loops
    iteration = 0
    
    while current_count < max_candles and iteration < max_iterations:
        iteration += 1
        batch_size = min(300, max_candles - current_count)  # API max is 300 per call
        
        last_time = get_last_candle_time(exchange, pair, timeframe)
        if last_time:
            # Fetch candles BEFORE the last one we have (going backwards in time)
            from datetime import datetime
            end_time = datetime.utcfromtimestamp(last_time).isoformat()
            print(f"[{pair}_{timeframe}] Batch {iteration}: Backfilling {batch_size} candles before {end_time}")
            candles = get_candles_with_retry(pair=pair, numcandles=batch_size, timeframe=timeframe, 
                                            exchange=exchange, end_time=end_time)
        else:
            # No data yet, fetch most recent candles
            print(f"[{pair}_{timeframe}] Batch {iteration}: Initial fetch of {batch_size} candles")
            candles = get_candles_with_retry(pair=pair, numcandles=batch_size, timeframe=timeframe, exchange=exchange)
        
        if candles and len(candles) > 0:
            insert_candles(exchange, candles, pair, timeframe, numcandles, redis_client)
            old_count = current_count
            current_count = get_candle_count(exchange, pair, timeframe)
            print(f"[{pair}_{timeframe}] Progress: {current_count}/{max_candles} candles (+{current_count - old_count})")
            
            if len(candles) < batch_size:
                # API returned less than requested, we've reached historical limit
                print(f"[{pair}_{timeframe}] Backfill complete (API has no more historical data)")
                break
            
            # If we need more than 300 candles, continue iterating
            if current_count < max_candles:
                print(f"[{pair}_{timeframe}] Still need {max_candles - current_count} more, fetching next batch...")
                time.sleep(1.5)  # Longer pause between large backfill batches
        else:
            print(f"[{pair}_{timeframe}] No more candles available from API")
            break
    
    print(f"[{pair}_{timeframe}] Backfill finished: {current_count} candles in database (iterations: {iteration})")

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
            # Prepare all candle data as list of tuples for bulk insert
            candle_data = [
                (
                    numcandles - i + 1,  # candle_id (primary key)
                    candle[0],           # timestamp
                    candle[1],           # open
                    candle[2],           # high
                    candle[3],           # low
                    candle[4],           # close
                    candle[5]            # volume
                )
                for i, candle in enumerate(data, start=1)
            ]
            
            # Single bulk INSERT with ON DUPLICATE KEY UPDATE
            insert_query = f"""
                INSERT INTO {table_name} (id, time, open, high, low, close, volume)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    time = VALUES(time),
                    open = VALUES(open),
                    high = VALUES(high),
                    low = VALUES(low),
                    close = VALUES(close),
                    volume = VALUES(volume)
            """
            
            cursor.executemany(insert_query, candle_data)
            cnx.commit()
            
            last_close = data[-1][4]
            if last_close is not None:
                redis_key = f"{exchange}_{pair}"
                store_last_close_in_redis(redis_client, redis_key, last_close)

            print(f"Bulk inserted {len(data)} candles for {pair} at {timeframe} (table name: {table_name}).")

        except mysql.connector.Error as err:
            print(f"Error updating candles for {pair} at {timeframe}: {err}")
            cnx.rollback()  # Roll back any changes if an error occurs

        finally:
            cursor.close()  # Ensure the cursor is closed regardless of success or error
            cnx.close()  # Return connection to pool

# Main function to iterate over pairs and timeframes
def main():
    import sys
    
    # Initialize exchange and pairs
    pairs = ['OP-USD','SNX-USD','MORPHO-USD','BTC-USD', 'ETH-USD','POL-USD','ARB-USD','VELO-USD','AERO-USD','LINK-USD','SOL-USD','ETH-USD','BTC-USD','VELO-USD']
    timeframes = ['6h','6h','6h','6h', '6h', '6h', '6h', '15m', '6h', '6h','6h','1d','1d','1d']
    exchange = 'coinbase'
    numcandles = 300
    redis_client = connect_to_redis()
    
    # Check if this is initialization mode (--init flag or first run)
    is_init = '--init' in sys.argv
    
    for pair, timeframe in zip(pairs, timeframes):
        table_name = f'{exchange}_{pair}_{timeframe}'
        create_table(exchange, pair, timeframe)
        
        candle_count = get_candle_count(exchange, pair, timeframe)
        
        if is_init or candle_count < 250:
            # Initialization mode OR table has less than 250 candles (needs backfill)
            if candle_count == 0:
                print(f"\n=== EMPTY TABLE: Backfilling {exchange} {pair} {timeframe} ===")
            elif candle_count < 250:
                print(f"\n=== INCOMPLETE DATA ({candle_count} candles): Backfilling {exchange} {pair} {timeframe} ===")
            else:
                print(f"\n=== INIT MODE: Checking {exchange} {pair} {timeframe} ===")
            backfill_missing_candles(exchange, pair, timeframe, numcandles, redis_client, max_candles=300)
        else:
            # Always fetch and insert all 300 candles - IDs ensure no table growth
            print(f"[{pair}_{timeframe}] Fetching and updating 300 candles (current: {candle_count} candles)")
            candles = get_candles_with_retry(exchange=exchange, pair=pair, numcandles=numcandles, timeframe=timeframe)
            
            if candles:
                insert_candles(exchange, candles, pair, timeframe, numcandles, redis_client)
            else:
                print(f"[{pair}_{timeframe}] Failed to fetch candles")
        
        time.sleep(1)  # Rate limit protection

if __name__ == "__main__":
    main()
