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
    # Retrieve the first message from the database
    select_query = "SELECT channel, message FROM messages WHERE platform = %s ORDER BY timestamp ASC LIMIT 1"
    cursor.execute(select_query,(platform,))
    result = cursor.fetchone()
    delete_query = "DELETE FROM messages WHERE platform = %s ORDER BY timestamp ASC LIMIT 1"
    cursor.execute(delete_query,(platform,))

    # Commit the changes and close the connection
    cnx.commit()
    #cnx.close()

    # Return the retrieved message
    if result:
        return result[0], result[1]
    else: 
        return None

