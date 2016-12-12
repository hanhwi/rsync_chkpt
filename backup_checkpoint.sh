#!/bin/bash

#################### Snapshot utility for daily backup ####################
unset PATH

RSYNC="/usr/bin/rsync"
RM="/bin/rm"
MV="/bin/mv"
CP="/bin/cp"
LS="/bin/ls"
SORT="/usr/bin/sort"
TOUCH="/usr/bin/touch"
LOGGER="/usr/bin/logger"

#################### ARGUMENTS ####################

TARGET_DIR=$1 # target dir to make a snapshot
len_td=$(( ${#TARGET_DIR} - 1))
if [ ${TARGET_DIR:$len_td:1} == '/' ];then
    TARGET_DIR=${TARGET_DIR:0:$len_td}
fi
BACKUP_DIR=$2
DISK_QUOTA=$3
MAX_HOURLY_SNAPSHOT=6
MAX_DAILY_SNAPSHOT=10
MAX_WEEKLY_SNAPSHOT=4
MAX_MONTLY_SNAPSHOT=12

if ! [ -d "$TARGET_DIR" ];then
    echo "TARGET_DIR:${TARGET_DIR} does not exists."
    exit 1
fi

if ! [ -d "$BACKUP_DIR" ];then
    echo "BACKUP_DIR:${TARGET_DIR} does not exists."
    exit 1
fi

function rotate_snapshots() {
    # Rotate snapshots
    # Ex) hourly.0 -> hourly.1 , hourly.1 -> hourly.2
    # ARG1: snapshot category
    # ARG2: maximum number of snapshots of the given category
    # ARG3 (optional): the last of previous category snapshot
    
    category=$1
    max=$2
    prev=$3
    echo "rotate_snapshots" $1 $2 $3

    snapshots=(`$LS -d $BACKUP_DIR/${category}.[0-9]* 2> /dev/null | $SORT -n -k2 -t. -r`)
    echo ${snapshots[@]}

    if [ ${#snapshots[@]} -ne 0 ];then
        last_snapshot=${snapshots[0]}
        idx=${last_snapshot##*.}
        echo $idx
        echo $max
        if [ "$(($idx + 1))" -eq "$max" ];then
            $RM -r $last_snapshot
            snapshots=(${snapshots[@]:1})
        fi
    fi
    
    for s in "${snapshots[@]}";do
        idx=${s##*.}
        $MV $s $BACKUP_DIR/$category.$(($idx + 1))
    done
    
    if [ "$prev" != "" ];then
        $MV $prev $BACKUP_DIR/${category}.0
        $LOGGER "Created backup ($0) $prev"
    fi
}

function last_snapshot() {
    # ARG1: snapshot category
    category=$1
    snapshots=(`$LS -d $BACKUP_DIR/${category}.[0-9]* 2> /dev/null | $SORT -n -k2 -t. -r`)
    if [ ${#snapshots[@]} -ne 0 ];then 
        echo ${snapshots[0]}
    else
        echo ""
    fi
}

# Make montly snapshot @ the first day of the monthp
dm=`/bin/date +%d`
monthly_marker="${BACKUP_DIR}/monthly_marker"
if [ "${dm}" == "1" ];then
    if [ ! -e "$monthly_marker" ];then
        $TOUCH $monthly_marker
        last=$(last_snapshot "weekly")
        rotate_snapshots "montly" $MAX_MONTLY_SNAPSHOT $last
    fi
else
    $RM $monthly_marker 2> /dev/null
fi

# Make weekly snapshot @ the first day of the week
# Check already make this week's snapshot
wd=`/bin/date +%u`
weekly_marker="${BACKUP_DIR}/weekly_marker"
if [ "${wd}" == "1" ];then
    if [ ! -e "$weekly_marker" ];then
        $TOUCH $weekly_marker
        last=$(last_snapshot "daily")
        echo "week"$last
        rotate_snapshots "weekly" $MAX_WEEKLY_SNAPSHOT $last
    fi
else
    $RM $weekly_marker 2> /dev/null
fi

# Make daily snapshot @ 00:00
hour=`/bin/date +%H`
# Check already make today's snapshot
daily_marker="${BACKUP_DIR}/daily_marker"
if [ "${hour}" == "01" ];then
    if [ ! -e "$daily_marker" ];then
        $TOUCH "$daily_marker"
        last=$(last_snapshot "hourly")
        rotate_snapshots "daily" $MAX_DAILY_SNAPSHOT $last
    fi
else
    $RM $hourly_marker 2> /dev/null
fi

# Check current disk usage and remove old snapshots
# Make hourly snapshot
rotate_snapshots "hourly" $MAX_HOURLY_SNAPSHOT ""
$RSYNC \
    -a -v --delete --link-dest "../hourly.1" \
    "${TARGET_DIR}" "${BACKUP_DIR}/hourly.0"
if [ "$?" != "0" ];then
    $LOGGER "Creating daily backup failed ($0)"
else
    $LOGGER "Created daily backup ($1) to ${BACKUP_DIR}/hourly.0"
fi
