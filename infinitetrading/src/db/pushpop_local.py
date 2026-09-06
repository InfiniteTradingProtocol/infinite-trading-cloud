"""
Local MySQL message queue for Infinite Trading
Uses the local MySQL instance (127.0.0.1) for message storage
"""

import mysql.connector
import sys
import os
from datetime import datetime

# Local MySQL connection
def get_local_connection():
    """Connect to local MySQL instance"""
    try:
        # Get credentials from environment variables (LOCAL MySQL)
        db_user = os.getenv('db_user_local') or os.getenv('DB_USER_LOCAL')
        db_password = os.getenv('db_password_local') or os.getenv('DB_PASSWORD_LOCAL')
        
        if not db_user or not db_password:
            raise ValueError("Missing db_user_local or db_password_local environment variables")
        
        cnx = mysql.connector.connect(
            host='127.0.0.1',
            port=3306,
            user=db_user,
            password=db_password,
            database='infinitetrading'
        )
        return cnx
    except mysql.connector.Error as e:
        print(f"[LOCAL MYSQL ERROR] Failed to connect: {e}")
        raise

def push_message(platform, channel, message):
    """
    Push a message to the local MySQL database
    
    Args:
        platform: 'slack' or 'discord'
        channel: Channel name (e.g., '#error-logs')
        message: Message content
    """
    try:
        cnx = get_local_connection()
        cursor = cnx.cursor()
        timestamp = datetime.now()
        
        # Insert the message into the database
        insert_query = "INSERT INTO messages (timestamp, platform, channel, message) VALUES (%s, %s, %s, %s)"
        cursor.execute(insert_query, (timestamp, platform, channel, message))
        print(f"[LOCAL MYSQL] Message inserted to {platform} queue")
        
        # Commit the changes and close the connection
        cnx.commit()
        cursor.close()
        cnx.close()
        
    except mysql.connector.Error as e:
        print(f"[LOCAL MYSQL ERROR] Failed to push message: {e}")
        if 'cnx' in locals():
            cnx.rollback()
            cnx.close()


def pop_message(platform):
    """
    Pop the oldest message from the local MySQL database
    
    Args:
        platform: 'slack' or 'discord'
        
    Returns:
        Tuple of (channel, message) or None if queue is empty
    """
    result = None
    
    try:
        cnx = get_local_connection()
        cursor = cnx.cursor()
        
        # Use SELECT ... FOR UPDATE to lock the row, then delete it atomically
        # This prevents race conditions when multiple processes try to pop messages
        select_query = "SELECT channel, message, timestamp FROM messages WHERE platform = %s ORDER BY timestamp ASC LIMIT 1 FOR UPDATE"
        cursor.execute(select_query, (platform,))
        result = cursor.fetchone()
        
        if result:
            channel, message, timestamp = result
            # Delete the specific message by timestamp and message to ensure we delete what we selected
            delete_query = "DELETE FROM messages WHERE platform = %s AND message = %s AND timestamp = %s LIMIT 1"
            cursor.execute(delete_query, (platform, message, timestamp))
            cnx.commit()
            cursor.close()
            cnx.close()
            return channel, message
        else:
            cnx.commit()
            cursor.close()
            cnx.close()
            return None
            
    except mysql.connector.errors.DatabaseError as e:
        # If we get a lock timeout or other DB error, rollback and return None
        print(f"[LOCAL MYSQL ERROR] Database error in pop_message: {e}")
        if 'cnx' in locals():
            cnx.rollback()
            cnx.close()
        return None
    except Exception as e:
        print(f"[LOCAL MYSQL ERROR] Unexpected error in pop_message: {e}")
        if 'cnx' in locals():
            cnx.rollback()
            cnx.close()
        return None
