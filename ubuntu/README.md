Check IP's generating traffic

awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -nr | head -20


Check endpoints traffic example

grep "/.env" /var/log/nginx/access.log | wc -l

Monitor IO

sudo iotop -o

