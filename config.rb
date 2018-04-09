
DATABASE = {
        adapter: "postgresql",
        database: "scheduler_worker"
}

WORKER_NAME = `hostname`.strip
SEAPIG_URI = 'http://scheduler-server/seapig'
SCHEDULER_URI = 'http://scheduler-server'
EXTERNAL_SCHEDULER_URI = 'http://external-scheduler-name/'
DASHBOARD_URI = 'http://dashboard-server/dashboard/'

PROXY = false
OBS_URL = "http://obs-server/build"
OBS_USER = "user"
OBS_PASS = "pass"

RABBIT_HOST="rabbit-server"
RABBIT_PORT=5672
RABBIT_USER="user"
RABBIT_PASS="pass"

MECHATOUCH_URL = "http://mechatouch-server/"
SCHEDULER_SERVER_ROOT = '/opt/scheduler/latest'
SCHEDULER_WORKER_ROOT = '/opt/tester/scheduler-worker'
