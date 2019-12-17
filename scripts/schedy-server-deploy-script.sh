#!/bin/bash

trap trap_handler EXIT
trap trap_handler ERR

set -e
#set -x

#############################################################################
# Set by cli
#############################################################################
REPO_FOLDER=""

CLEAN_GEMFILE_LOCK=0
CLEAN_VENDOR_CACHE=0
CLEAN_BUNDLER_GIT_FOLDER=0
DO_GIT_TAG=0
DO_BUNDLE=0
DO_ROLLOUT=0

VERBOSE_RM=""
VERBOSE_TAR=""

DEPLOYHOST=""

#############################################################################
# 'Fixed' settings
#############################################################################
LOCK_FOLDER="/tmp/scheduler_deploy.lock"
HAVE_LOCK=0

BUNDLER_GIT_PATH="${HOME}/.gem/ruby/cache/bundler/git"

PROJECT_SERVER_BUNDELS="reporters creator hooks"

SERVER_GIT_NAME="scheduler-server"
PROJECT_GIT_NAME="scheduler-project"

FEDORA_VERSION="26"

REMOTE_TEMP_FOLDER='/tmp/scheduler-server-deploy/'

# rake needs a db to pre-compile stuff
export DATABASE_URL=postgresql://user:pass@127.0.0.1/dbname

#############################################################################
# to be set later, based on cli options
#############################################################################
WORKER_GIT_PATH=""
SERVER_GIT_PATH=""
PROJECT_GIT_PATH=""

SERVER_GIT_VERSION=""
PROJECT_GIT_VERSION=""

#############################################################################
# Further down are dragons, nothing to configure there...
#############################################################################

#############################################################################
#############################################################################
## FUNCTIONS
#############################################################################
#############################################################################

trap_handler()
{
    if [[ $HAVE_LOCK -eq 1 ]]; then
        echo "Clean up"
        rm -rf ${VERBOSE_RM} ${LOCK_FOLDER}
    fi
}

usage()
{
    cat <<EOF
A deploy helper script.

Usage:
   $0 -r <GIT_REPO_PATH> -d <DEPLOY_HOST> [OPTIONS]

e.g.
   $0 -r \$HOME/git-repos/ -d deploy-host [OPTIONS]

Mandatory Options:
   -r | --repo-folder       The base folder where the repos are, it expects
                            following names (can be symlinks):
                            scheduler-server -> contains open source part of
                                                scheduler server
                            scheduler-project -> the project specific code of
                                                 scheduler server
   -d | --deploy-host       Hostname or IP of the deploy server
Options:
   -v | --verbose           Enable verbose output (e.g. tar and rm)
   -h | --help              This help
   -t | --tag               Tag the git repos
   -c | --clean             Clean Gemfile.lock and related stuff
   -b | --bundle            Create vendor/cache bundle
   -o | --roll-out          switch symlink and restart container
   --debug                  Debug mode (set -x)
EOF

    # exit if any argument is given
    [[ -n "$1" ]] && exit 1
}

parse_commandline()
{
    while [[ ${1:-} ]]; do
        case "$1" in
            --debug) shift
                set -x
                ;;
            -h | --help) shift
                usage quit
                ;;
            -v | --verbose) shift
                VERBOSE_RM="-v"
                VERBOSE_TAR="-v"
                ;;
            -t | --tag) shift
                DO_GIT_TAG=1
                ;;
            -c | --clean) shift
                CLEAN_GEMFILE_LOCK=1
                CLEAN_VENDOR_CACHE=1
                CLEAN_BUNDLER_GIT_FOLDER=1
                DO_BUNDLE=1
                ;;
            -r | --repo-folder) shift
                REPO_FOLDER=$1; shift
                ;;
            -d | --deploy-host) shift
                DEPLOYHOST=$1; shift
                ;;
            -b | --bundle) shift
                DO_BUNDLE=1
                ;;
            -o | --roll-out) shift
                DO_ROLLOUT=1
                ;;
            *) 
                break
                ;;
        esac
    done

    [[ -z $REPO_FOLDER ]] && usage quit
    REPO_FOLDER=$(readlink -f ${REPO_FOLDER})

    [[ ! -d $REPO_FOLDER ]] && { echo "ERROR: given directory [${REPO_FOLDER}] does not exist"; exit 1; }
    SERVER_GIT_PATH="${REPO_FOLDER}/${SERVER_GIT_NAME}"

    [[ ! -d $SERVER_GIT_PATH ]] && { echo "ERROR: given directory [${SERVER_GIT_PATH}] does not exist"; exit 1; }

    PROJECT_GIT_PATH="${REPO_FOLDER}/${PROJECT_GIT_NAME}"
    [[ ! -d $PROJECT_GIT_PATH ]] && { echo "ERROR: given directory [${PROJECT_GIT_PATH}] does not exist"; exit 1; }

    [[ -z $DEPLOYHOST ]] && usage quit

    NOW=$(LC_TIME=C date)
    TIMESTAMP=$(date +'%Y%m%d%H%M.%S' -d "${NOW}")
    RELEASE=$(date +'%Y%m%d%H%M%S' -d "${NOW}")
    set_git_version
}

clean_gemfile_locks()
{
    if [[ $CLEAN_GEMFILE_LOCK -eq 1 ]]; then
        rm -f ${VERBOSE_RM} ${SERVER_GIT_PATH}/Gemfile.lock
        for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
            rm -f ${VERBOSE_RM} ${PROJECT_GIT_PATH}/${BUNDLE}/Gemfile.lock
        done
    fi
}

clean_vendor_caches()
{
    if [[ $CLEAN_VENDOR_CACHE -eq 1 ]]; then
        rm -rf ${VERBOSE_RM} ${WORKER_GIT_PATH}/vendor/cache
        rm -rf ${VERBOSE_RM} ${SERVER_GIT_PATH}/vendor/cache
        for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
            rm -rf ${VERBOSE_RM} ${PROJECT_GIT_PATH}/${BUNDLE}/vendor/cache
        done
    fi
}

clean_bundler_git_folder()
{
    if [[ $CLEAN_BUNDLER_GIT_FOLDER -eq 1 ]]; then
        rm -rf ${VERBOSE_RM} ${BUNDLER_GIT_PATH}
    fi
}

run_command_in_server_folder()
{
    pushd ${SERVER_GIT_PATH}
    eval $1
}

install_project_bundels()
{
    for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
        pushd ${PROJECT_GIT_PATH}/${BUNDLE}
        bundle install
    done
}

bundle_install_local()
{
    if [[ $CLEAN_GEMFILE_LOCK -eq 1 ]]; then
        run_command_in_server_folder "bundle install"
        install_project_bundels
    fi
}

create_tarballs()
{
    run_command_in_server_folder "rake build:tarball"
    pushd ${PROJECT_GIT_PATH}/deploy-server
    tar ${VERBOSE_TAR} -c -j --exclude=deploy-server/scheduler-server-project.tar.bz2 --exclude=docker-* --exclude=.bundle -f  scheduler-server-project.tar.bz2  ../*
}

set_git_version()
{
    SERVER_GIT_VERSION=$(run_command_in_server_folder "git log --pretty=oneline --max-count=1" | tr \' _)
    pushd ${PROJECT_GIT_PATH}
    PROJECT_GIT_VERSION=$(git log --pretty=oneline --max-count=1 | tr \' _)
}

git_tag()
{
    if [[ $DO_GIT_TAG -eq 1 ]]; then
        run_command_in_server_folder "git tag server-${RELEASE}"
        run_command_in_server_folder "git push origin server-${RELEASE}"
        pushd ${PROJECT_GIT_PATH}
        git tag "server-${RELEASE}"
#        git push origin "server-${RELEASE}"
    fi
}

precomple_assets()
{
    pushd ${PROJECT_GIT_PATH}/assets
    bundle install
    bundle exec rake assets:precompile
}

transfer_tarballs()
{
    run_command_in_server_folder "scp deploy/scheduler-server.tar.bz2 ${DEPLOYHOST}:${REMOTE_TEMP_FOLDER}/"
    pushd ${PROJECT_GIT_PATH}/deploy-server
    scp scheduler-server-project.tar.bz2 ${DEPLOYHOST}:${REMOTE_TEMP_FOLDER}/
}

package_bundels()
{
    if [[ $DO_BUNDLE -eq 1 ]]; then
        run_command_in_server_folder "bundle package --all"        
        package_project_bundels
    fi
}

package_project_bundels()
{
    for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
        pushd ${PROJECT_GIT_PATH}/${BUNDLE}
        bundle package --all
    done
}

extract_tarballs()
{
    FOLDER="/var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}"
    ssh ${DEPLOYHOST} "sudo mkdir ${FOLDER};sudo  tar -xvj -C ${FOLDER} -f ${REMOTE_TEMP_FOLDER}/scheduler-server.tar.bz2"
    run_command_in_server_folder "scp deploy/database.yml ${DEPLOYHOST}:${REMOTE_TEMP_FOLDER}/"
    ssh ${DEPLOYHOST} "sudo mv ${REMOTE_TEMP_FOLDER}/database.yml ${FOLDER}/config/"
    ssh ${DEPLOYHOST} "echo '${SERVER_GIT_VERSION}' > ${REMOTE_TEMP_FOLDER}/git-version;sudo mv ${REMOTE_TEMP_FOLDER}/git-version ${FOLDER}/git-version"
    FOLDER="${FOLDER}/project"
    ssh ${DEPLOYHOST} "sudo mkdir ${FOLDER};sudo tar -xvj -C ${FOLDER} -f ${REMOTE_TEMP_FOLDER}/scheduler-server-project.tar.bz2"
    ssh ${DEPLOYHOST} "echo '${PROJECT_GIT_VERSION}' > ${REMOTE_TEMP_FOLDER}/git-version;sudo mv ${REMOTE_TEMP_FOLDER}/git-version ${FOLDER}/git-version"
    ssh ${DEPLOYHOST} "exx 'ln -s /data/scheduler-storage /opt/scheduler/${RELEASE}/storage' "
    ssh ${DEPLOYHOST} "exx 'ln --relative --symbolic /opt/scheduler/${RELEASE}/project/deploy-server/seapig2zabbix.rb /opt/scheduler/${RELEASE}/seapig2zabbix.rb' "
    ssh ${DEPLOYHOST} "exx 'chown -R schedy.schedy /opt/scheduler/${RELEASE}'"
}

bundle_install_deployment()
{
    ssh ${DEPLOYHOST} "exx 'su -c \"cd /opt/scheduler/${RELEASE}; bundle config build.nokogiri --use-system-libraries; bundle install --deployment\" schedy'"
    for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
        ssh ${DEPLOYHOST} "exx 'su -c \"cd /opt/scheduler/${RELEASE}/project/${BUNDLE}/; bundle config build.nokogiri --use-system-libraries; bundle install --deployment\" schedy'"
    done
}

set_time_stamp()
{
    FOLDER="/var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}"
    ssh ${DEPLOYHOST} "sudo find ${FOLDER} -type f -print0 |sudo xargs -0 touch -t ${TIMESTAMP}"
    ssh ${DEPLOYHOST} "sudo find ${FOLDER} -type d -print0 |sudo xargs -0 touch -t ${TIMESTAMP}"
    ssh ${DEPLOYHOST} "sudo find ${FOLDER} -type l -print0 |sudo xargs -0 touch -h -t ${TIMESTAMP}"
}

roll_out()
{
    if [[ $DO_ROLLOUT -eq 1 ]]; then
        ssh ${DEPLOYHOST} "sudo systemctl stop f${FEDORA_VERSION}_scheduler_server.service"
        ssh ${DEPLOYHOST} "sudo rm -f /var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/latest;sudo cd /var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/ ;sudo ln -s ${RELEASE} latest"
        ssh ${DEPLOYHOST} "sudo systemctl start f${FEDORA_VERSION}_scheduler_server.service"
    fi
}

create_remote_temp_folder()
{
    ssh ${DEPLOYHOST} "mkdir -p ${REMOTE_TEMP_FOLDER}"
}

clean_remote_temp_folder()
{
    ssh ${DEPLOYHOST} "rm -rf ${VERBOSE_RM} ${REMOTE_TEMP_FOLDER}"
}
#############################################################################
#############################################################################
## MAIN
#############################################################################
#############################################################################

parse_commandline $@

while ! mkdir ${LOCK_FOLDER}; do
    echo "Didn't get look... sleep..."
    sleep 3
done
    HAVE_LOCK=1
    clean_bundler_git_folder
    clean_vendor_caches
    clean_gemfile_locks

    precomple_assets

    package_bundels

    create_tarballs

    create_remote_temp_folder

    transfer_tarballs
rm -rvf ${LOCK_FOLDER} && HAVE_LOCK=0

extract_tarballs

bundle_install_deployment

set_time_stamp

roll_out

git_tag

clean_remote_temp_folder

echo "RELEASE: ${RELEASE}"

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
