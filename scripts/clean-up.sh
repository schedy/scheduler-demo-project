#!/bin/bash
#set -x

trap trap_handler EXIT
trap trap_handler ERR

pushd `dirname $0` > /dev/null
PATH_SCRIPT=`pwd -P`
popd > /dev/null
SCHEDULER_STORAGE_PATH=`realpath $PATH_SCRIPT/../../storage`


DEBUG=0
RM_OPTION="-f -r"

HIGH_PERCENTAGE=85
LOW_PERCENTAGE=70

MIN_ABS=10485760
MAX_ABS=20971520

AGE="-mtime +10"

LOCK_FOLDER="/tmp/scheduler-storage-cleaner.lock"
HAVE_LOCK=0

if [ -f /etc/storage-cleaner.rc ]; then
	source /etc/storage-cleaner.rc
fi

TASK_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/tasks/ -maxdepth 1 -mindepth 1 -type d ${AGE})
UNPACKED_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/unpacked/ -maxdepth 1 -mindepth 1 -type d ${AGE})
RPM_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.rpm')
IPK_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.ipk')
ZIP_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.zip')
SDCARD_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.sdcard')
OVF_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.ovf')
VMDK_FIND_CMD=(${SCHEDULER_STORAGE_PATH}/rpms/ ${AGE} -type f -name '*.vmdk')

if [[ $DEBUG -ge 1 ]] ; then
	RM_OPTION="${RM_OPTION} -v"
fi

trap_handler()
{
    if [[ $HAVE_LOCK -eq 1 ]]; then
        log_info "Clean up lock folder"
        rm -rf ${LOCK_FOLDER}
    fi
}

get_usage_percentage() {
	echo $(echo $(df ${SCHEDULER_STORAGE_PATH} | tail -1 | grep -E -o ' +[0-9]+ +[0-9]{1,3}\%' | sed 's/%//') | awk '{ print $2 }')
}

get_available_abs() {
	echo $(echo $(df ${SCHEDULER_STORAGE_PATH} | tail -1 | grep -E -o ' +[0-9]+ +[0-9]{1,3}\%' | sed 's/%//') | awk '{ print $1 }')
}

log_info() {
	if [[ $DEBUG -gt 0 ]] ; then
		echo -e $*
	fi
	/bin/logger -t STORAGE-CLEANUP -- "{$$} - $*"
}

log_debug() {
	if [[ $DEBUG -gt 0 ]] ; then
		log_info "$*"
	fi
}

isFlashingOngoing() {
	pgrep -f "ruby hufla.rb" > /dev/null
	HRC=$?
	pgrep -f "/opt/SEGGER/JLink/JLinkExe" > /dev/null
	JRC=$?
	if [[ $HRC == 0 || $JRC == 0 ]] ; then
		log_info "Flashing on going, do not delete anything and exit!"
		log_info "(on quit) disk usage in %: $(get_usage_percentage)"
		log_info "(on quit) disk space available in bytes: $(get_available_abs)"
		exit 1
	fi
}


clean() {
	cleanOldestFrom TASK_FIND_CMD[@]
	if [[ $? != 0 ]]; then
		log_debug "No more task folders to delete?!"
		cleanOldestFrom UNPACKED_FIND_CMD[@]
		if [[ $? != 0 ]]; then
			log_debug "No more unpacked folders to delete?!"
			cleanOldestFrom SDCARD_FIND_CMD[@]
			if [[ $? != 0 ]]; then
				log_debug "No more sdcard's to delete?!"
				cleanOldestFrom RPM_FIND_CMD[@]
				if [[ $? != 0 ]]; then
					log_debug "No more rpms to delete?!"
					cleanOldestFrom IPK_FIND_CMD[@]
					if [[ $? != 0 ]]; then
						log_debug "No more ipks to delete?!"
						cleanOldestFrom ZIP_FIND_CMD[@]
						if [[ $? != 0 ]]; then
							log_debug "No more zips to delete?!"
							cleanOldestFrom SDCARD_FIND_CMD[@]
							if [[ $? != 0 ]]; then
								log_debug "No more sdcards to delete?!"
								cleanOldestFrom OVF_FIND_CMD[@]
								if [[ $? != 0 ]]; then
									log_debug "No more ovfs to delete?!"
									cleanOldestFrom VMDK_FIND_CMD[@]
									if [[ $? != 0 ]]; then
										log_debug "No more vmdks to delete?!"
										echo "Disk space critical!"
										break
									fi
								fi
							fi
						fi
					fi
				fi
			fi
		fi
	fi
}

cleanPercentageBased() {
	while [[ $(get_usage_percentage) -gt $LOW_PERCENTAGE ]]; do
		clean
	done
}

cleanAbsBased() {
	while [[ $(get_available_abs) -lt $MAX_ABS ]]; do
		clean
	done
}

cleanOldestFrom() {
	declare -a findArgAry=("${!1}")
	while IFS= read -r -d $'\0' line ; do
		set -e
		file="${line#* }"
		chmod -R u+w "$file"
		rm $RM_OPTION "$file"
		set +e
		return 0
	done < <(find "${findArgAry[@]}" -printf '%T@ %p\0' 2>/dev/null | sort -z -n)
	return 1
}

#############################################################################
#############################################################################
## MAIN
#############################################################################
#############################################################################

if ! mkdir ${LOCK_FOLDER} 2>/dev/null; then
	log_info "Lockfile exists storage-cleaner, already running!? Exit!"
	exit 0
fi
HAVE_LOCK=1

isFlashingOngoing

log_info "(before) disk usage in %: $(get_usage_percentage)"
if [[ $(get_usage_percentage) -ge $HIGH_PERCENTAGE ]]; then
	cleanPercentageBased
fi
log_info " (after) disk usage in %: $(get_usage_percentage)"


isFlashingOngoing

log_info "(before) disk space available in bytes: $(get_available_abs)"
if [[ $(get_available_abs) -le $MIN_ABS ]]; then
	cleanAbsBased
fi
log_info " (after) disk space available in bytes: $(get_available_abs)"

rm -rf ${LOCK_FOLDER} && HAVE_LOCK=0

