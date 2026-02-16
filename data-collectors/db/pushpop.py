import mysql.connector
import sys
import credentials
from datetime import datetime
cnx = credentials.cnx

def push_message(platform,channel,message):
    # Connect to the MySQL database
    # Create a cursor object to interact with the database
    cursor = cnx.cursor()
    timestamp = datetime.now()
    # Insert the message into the database
    insert_query = "INSERT INTO messages (timestamp, platform, channel, message) VALUES (%s, %s, %s, %s)"
    cursor.execute(insert_query, (timestamp, platform, channel, message))
    print("Message inserted successfully")
    # Commit the changes and close the connection
    cnx.commit()
    #cnx.close()

def pop_message(platform):
    # Connect to the MySQL database
    # Create a cursor object to interact with the database
    cursor = cnx.cursor()
    result = None
    
    try:
        # Use SELECT ... FOR UPDATE to lock the row, then delete it atomically
        # This prevents race conditions when multiple processes try to pop messages
        select_query = "SELECT channel, message, timestamp FROM messages WHERE platform = %s ORDER BY timestamp ASC LIMIT 1 FOR UPDATE"
        cursor.execute(select_query, (platform,))
        result = cursor.fetchone()
        
        if result:
            channel, message, timestamp = result
            # Delete the specific message by timestamp and message (part of PK) to ensure we delete what we selected
            delete_query = "DELETE FROM messages WHERE platform = %s AND message = %s AND timestamp = %s LIMIT 1"
            cursor.execute(delete_query, (platform, message, timestamp))
            cnx.commit()
            return channel, message
        else:
            cnx.commit()
            return None
            
    except mysql.connector.errors.DatabaseError as e:
        # If we get a lock timeout or other DB error, rollback and return None
        cnx.rollback()
        print(f"Database error in pop_message: {e}")
        return None
    except Exception as e:
        cnx.rollback()
        print(f"Unexpected error in pop_message: {e}")
        return None

