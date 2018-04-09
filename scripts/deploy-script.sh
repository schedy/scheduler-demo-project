#!/bin/bash

trap trap_handler EXIT
trap trap_handler ERR

set -e
#set -x

#############################################################################
# Set by cli
#############################################################################
TYPE=""
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
TSHOSTNAME=""

SCHEDULER_IP=""
DASHBOARD_IP=""

#############################################################################
# 'Fixed' settings
#############################################################################
RABBIT_IP="172.17.0.1"

LOCK_FOLDER="/tmp/scheduler_project.lock"
HAVE_LOCK=0

BUNDLER_GIT_PATH="${HOME}/.gem/ruby/cache/bundler/git"

PROJECT_SERVER_BUNDELS="reporters creator hooks"
PROJECT_WORKER_BUNDELS="executors"

WORKER_GIT_NAME="scheduler-worker"
SERVER_GIT_NAME="scheduler-server"
PROJECT_GIT_NAME="scheduler-project"

FEDORA_VERSION="26"

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
   $0 -r <GIT_REPO_PATH> -y <TYPE> -d <DEPLOY_HOST> [OPTIONS]

e.g.
   $0 -r \$HOME/git-repos/ -y worker -d deploy-host -w teststation-001 [OPTIONS]

Mandatory Options:
   -r | --repo-folder       The base folder where the repos are
   -y | --type              Server or Worker
   -d | --deploy-host       Hostname of the deploy server
   -w | --worker-name       Hostname of the worker (teststation)
                            if type is 'worker' this is mandatory
   -s | --scheduler-ip      IP address where scheduler is reachable
   -a | --dashboard-ip      IP address where dashboard is reachable
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
            -y | --type) shift
                TYPE=$1; shift
                ;;
            -d | --deploy-host) shift
                DEPLOYHOST=$1; shift
                ;;
            -s | --scheduler-ip) shift
                SCHEDULER_IP=$1; shift
                ;;
            -a | --dashboard-ip) shift
                DASHBOARD_IP=$1; shift
                ;;
            -w | --worker-name) shift
                TSHOSTNAME=$1; shift
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
    WORKER_GIT_PATH="${REPO_FOLDER}/${WORKER_GIT_NAME}"
    SERVER_GIT_PATH="${REPO_FOLDER}/${SERVER_GIT_NAME}"
    PROJECT_GIT_PATH="${REPO_FOLDER}/${PROJECT_GIT_NAME}"

    [[ -z $DEPLOYHOST ]] && usage quit

    [[ -z $TYPE ]] && usage quit
    if [[ $TYPE == "worker" ]]; then
        [[ -z $TSHOSTNAME ]] && usage quit
    fi

    NOW=$(LC_TIME=C date)
    TIMESTAMP=$(date +'%Y%m%d%H%M.%S' -d "${NOW}")
    RELEASE=$(date +'%Y%m%d%H%M%S' -d "${NOW}")
    set_git_version
}

clean_gemfile_locks()
{
    if [[ $CLEAN_GEMFILE_LOCK -eq 1 ]]; then
        case  $TYPE  in
            worker)
                rm -f ${VERBOSE_RM} ${WORKER_GIT_PATH}/Gemfile.lock
            ;;
            server)
                rm -f ${VERBOSE_RM} ${SERVER_GIT_PATH}/Gemfile.lock
                for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
                    rm -f ${VERBOSE_RM} ${PROJECT_GIT_PATH}/${BUNDLE}/Gemfile.lock
                done
            ;;
            *)
            ;;
        esac
    fi
}

clean_vendor_caches()
{
    if [[ $CLEAN_VENDOR_CACHE -eq 1 ]]; then
        case  $TYPE  in
            worker)
                rm -rf ${VERBOSE_RM} ${WORKER_GIT_PATH}/vendor/cache
            ;;
            server)
                rm -rf ${VERBOSE_RM} ${SERVER_GIT_PATH}/vendor/cache
                for BUNDLE in ${PROJECT_SERVER_BUNDELS}; do
                    rm -rf ${VERBOSE_RM} ${PROJECT_GIT_PATH}/${BUNDLE}/vendor/cache
                done
            ;;
            *)
            ;;
        esac
    fi
}

clean_bundler_git_folder()
{
    if [[ $CLEAN_BUNDLER_GIT_FOLDER -eq 1 ]]; then
        rm -rf ${VERBOSE_RM} ${BUNDLER_GIT_PATH}
    fi
}

run_command_in_type_folder()
{
    case  $TYPE  in
        worker)
            pushd ${WORKER_GIT_PATH}
        ;;
        server)
            pushd ${SERVER_GIT_PATH}
        ;;
        *)
            echo "No Type given!? Can't install bundle"
            exit 1
        ;;
    esac
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
        run_command_in_type_folder "bundle install"
        install_project_bundels
    fi
}

create_tarballs()
{
    run_command_in_type_folder "rake build:tarball"
    pushd ${PROJECT_GIT_PATH}/deploy-${TYPE}
    tar ${VERBOSE_TAR} -c -j --exclude=deploy-${TYPE}/scheduler-${TYPE}-project.tar.bz2 --exclude=docker-* --exclude=.bundle -f  scheduler-${TYPE}-project.tar.bz2  ../*
}

set_git_version()
{
    SERVER_GIT_VERSION=$(run_command_in_type_folder "git log --pretty=oneline --max-count=1" | tr \' _)
    pushd ${PROJECT_GIT_PATH}
    PROJECT_GIT_VERSION=$(git log --pretty=oneline --max-count=1 | tr \' _)
}

git_tag()
{
    if [[ $DO_GIT_TAG -eq 1 ]]; then
        run_command_in_type_folder "git tag ${TYPE}-${RELEASE}"
        run_command_in_type_folder "git push origin ${TYPE}-${RELEASE}"
        pushd ${PROJECT_GIT_PATH}
        git tag "${TYPE}-${RELEASE}"
        git push origin "${TYPE}-${RELEASE}"
    fi
}

precomple_assets()
{
    pushd ${PROJECT_GIT_PATH}/assets
    bundle install
    bundle exec rake assets:precompile
}

clean_remote_target_folders()
{
    ssh ${DEPLOYHOST} "rm -rf ${VERBOSE_RM} /data/deploy/scheduler-${TYPE}/*"
}

transfer_tarballs()
{
    run_command_in_type_folder "scp deploy/scheduler-${TYPE}.tar.bz2 ${DEPLOYHOST}:/data/deploy/scheduler-${TYPE}/"
    pushd ${PROJECT_GIT_PATH}/deploy-${TYPE}
    scp scheduler-${TYPE}-project.tar.bz2 ${DEPLOYHOST}:/data/deploy/scheduler-${TYPE}/
}

package_bundels()
{
    if [[ $DO_BUNDLE -eq 1 ]]; then
        run_command_in_type_folder "bundle package --all"        
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
    ssh ${DEPLOYHOST} "sudo mkdir ${FOLDER};sudo  tar -xvj -C ${FOLDER} -f /data/deploy/scheduler-${TYPE}/scheduler-${TYPE}.tar.bz2"
    run_command_in_type_folder "scp deploy/database.yml ${DEPLOYHOST}:/data/deploy/scheduler-${TYPE}/"
    ssh ${DEPLOYHOST} "sudo mv /data/deploy/scheduler-${TYPE}/database.yml ${FOLDER}/config/"
    ssh ${DEPLOYHOST} "echo '${SERVER_GIT_VERSION}' > /data/deploy/scheduler-${TYPE}/git-version;sudo mv /data/deploy/scheduler-${TYPE}/git-version ${FOLDER}/git-version"
    FOLDER="${FOLDER}/project"
    ssh ${DEPLOYHOST} "sudo mkdir ${FOLDER};sudo tar -xvj -C ${FOLDER} -f /data/deploy/scheduler-${TYPE}/scheduler-${TYPE}-project.tar.bz2"
    ssh ${DEPLOYHOST} "echo '${PROJECT_GIT_VERSION}' > /data/deploy/scheduler-${TYPE}/git-version;sudo mv /data/deploy/scheduler-${TYPE}/git-version ${FOLDER}/git-version"
    #echo "mv config.rb config.rb.old and place newer config there"
    #ssh ${DEPLOYHOST} "cd /var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}/project/; mv config.rb config.rb.old"
    #scp "${PROJECT_GIT_PATH}/deploy-server/config.rb" "${DEPLOYHOST}:/var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}/project/"
    #echo "done..."
    ssh ${DEPLOYHOST} "exx 'ln -s /data/scheduler-storage /opt/scheduler/${RELEASE}/storage' "
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

do_restorecon()
{
    ssh ${DEPLOYHOST} "sudo mkdir -p /var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}/log/"
    ssh ${DEPLOYHOST} "exx 'chown schedy:schedy /opt/scheduler/${RELEASE}/log/'"
    echo "doing a restorecon... might take a while..."
    ssh ${DEPLOYHOST} "sudo restorecon -vr /var/lib/machines/f${FEDORA_VERSION}_scheduler_server/opt/scheduler/${RELEASE}/"
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

#    bundle_install_local

    package_bundels

    create_tarballs

    clean_remote_target_folders

    transfer_tarballs
rm -rvf ${LOCK_FOLDER} && HAVE_LOCK=0

extract_tarballs

bundle_install_deployment

set_time_stamp

#do_restorecon

roll_out

git_tag

echo "RELEASE: ${RELEASE}"

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
