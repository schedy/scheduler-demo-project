#!/bin/bash

RELEASE=${1}
SCHEDY_FOLDER="/var/lib/machines/f26_scheduler_server/opt/scheduler"
RAILS_LOG_FILE="${SCHEDY_FOLDER}/${RELEASE}/log/production.log"

pushd ${SCHEDY_FOLDER}
systemctl stop f26_scheduler_server.service
rm -f latest
ln -s ${RELEASE} latest
systemctl start f26_scheduler_server.service
popd

echo "Schedy services started..."

while ! [ -f ${RAILS_LOG_FILE} ]; do
    echo "File does not exist yet:"
    echo ${RAILS_LOG_FILE}
    echo "waiting..."
    sleep 3
done

echo "doing a 'restorecon' in ${SCHEDY_FOLDER}/${RELEASE}/"
restorecon -vr ${SCHEDY_FOLDER}/${RELEASE}/

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
