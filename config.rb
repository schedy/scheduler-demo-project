DATABASE = {
	adapter: "postgresql",
	database: "scheduler_worker"
}

WORKER_NAME = `hostname -s`.strip
SEAPIG_URI = 'http://scheduler-server/seapig'
SCHEDULER_URI = 'http://scheduler-server'
EXTERNAL_SCHEDULER_URI = 'http://external-scheduler-name/'
DASHBOARD_URI = 'http://dashboard-server/dashboard/'
ALM_URL = 'http://alm-server/qcbin'
ALM_CRED = 'SECRET'
GE_PROXY = false
OBS_URL = "http://obs-server/build"
OBS_USER = "user"
OBS_PASS = "pass"

RABBIT_HOST="rabbit-server"
RABBIT_PORT=5672
RABBIT_USER="user"
RABBIT_PASS="pass"
TESTRESULTS_FLOWDOCK_TOKEN = "TOKEN"
OBS_REPO_BASE_URL = "https:/obs-server/repos"
MECHATOUCH_URL = "http://mechatouch-server/"
SCHEDULER_SERVER_ROOT = '/opt/scheduler/latest'
SCHEDULER_WORKER_ROOT = '/opt/tester/scheduler-worker'
