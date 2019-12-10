#!/bin/bash

/bin/logger -t ZABBIX_SCHEDY -- "{$$} Looking for resources...!"

SQL="SELECT id, description #>> '{\"type\"}' as type FROM resources;"
RESOURCES=$(psql --field-separator=: --pset='format=unaligned' --quiet --tuples-only scheduler_worker --command "$SQL")

echo '{"data": ['
COMMA=''
for RESOURCE in ${RESOURCES}; do
	echo ${RESOURCE} | awk -F: "{print \"$COMMA{\\\"{#ID}\\\":\\\"\" \$1 \"\\\", \\\"{#TYPE}\\\":\\\"\" \$2 \"\\\"}\" }"
	COMMA=','
done
echo ']}'

exit 0
