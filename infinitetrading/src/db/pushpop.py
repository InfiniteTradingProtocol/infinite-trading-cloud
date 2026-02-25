import mysql.connector
import sys
import credentials
from datetime import datetime

def push_message(platform, channel, message):
    cnx = credentials.get_connection()
    try:
        cursor = cnx.cursor()
        timestamp = datetime.now()
        insert_query = "INSERT INTO messages (timestamp, platform, channel, message) VALUES (%s, %s, %s, %s)"
        cursor.execute(insert_query, (timestamp, platform, channel, message))
        print("Message inserted successfully")
        cnx.commit()
    finally:
        cursor.close()
        cnx.close()

def pop_message(platform):
    cnx = credentials.get_connection()
    result = None
    
    try:
        cursor = cnx.cursor()
        select_query = "SELECT channel, message, timestamp FROM messages WHERE platform = %s ORDER BY timestamp ASC LIMIT 1 FOR UPDATE"
        cursor.execute(select_query, (platform,))
        result = cursor.fetchone()
        
        if result:
            channel, message, timestamp = result
            delete_query = "DELETE FROM messages WHERE platform = %s AND message = %s AND timestamp = %s LIMIT 1"
            cursor.execute(delete_query, (platform, message, timestamp))
            cnx.commit()
            return channel, message
        else:
            cnx.commit()
            return None
            
    except mysql.connector.errors.DatabaseError as e:
        cnx.rollback()
        print(f"Database error in pop_message: {e}")
        return None
    except Exception as e:
        cnx.rollback()
        print(f"Unexpected error in pop_message: {e}")
        return None
    finally:
        cursor.close()
        cnx.close()
