#pip install mysql-connector-python
#pip install pymysql
import mysql.connector
import pymysql

def mysql_connect(user, hostname, port, password, dbname):
    mysql_connection = None
    mysql_connection = pymysql.connect(host=hostname,port=port,user=user,password=password,database=dbname)
    return mysql_connection

def mysql_read(mysql_connection, table_name):
    cursor = mysql_connection.cursor()
    cursor.execute(f"SHOW TABLES LIKE '{table_name}'")
    if not cursor.fetchone():
        print(f"Table '{table_name}' does not exist, please make sure your table is created into your MySQL")
        return None
    cursor.execute(f"SELECT * FROM {table_name}")
    table_content = cursor.fetchall()
    cursor.close()
    return table_content

def read_probabilities(mysql_connection):
    response = mysql_read(mysql_connection, table_name="model_probabilities_new")
    return response

# Usage example
mysql_connection = mysql_connect("richard_clare", "localhost", 3306, "AxDWeW8E7w8dSXJKsXsdfASXaxAD279347", "probabilities")
probabilities = read_probabilities(mysql_connection)
print(probabilities)

cursor = mysql_connection.cursor()
query = "SELECT * FROM model_probabilities WHERE model LIKE '%Zeus%' AND probability < 0.5"
cursor.execute(query)
result = cursor.fetchall()
cursor.close()

if result:
    for row in result:
        print(row)
else:
    print("No rows found.")
