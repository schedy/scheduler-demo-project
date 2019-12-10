#!/bin/bash

echo "The following files changed!"
CHECK_FOLDER=$(readlink -f $(dirname $(dirname $0))/../)
find $CHECK_FOLDER -type f -newer $CHECK_FOLDER/git-version | \
    grep -E -v '/log/production\.log$|/log/production\.log-[0-9]{8}\.gz|/log/development\.log$|/log/.*\.rb\.log$|/tmp/pids/server.pid$|.swp$'
