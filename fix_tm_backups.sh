#!/bin/bash
# Friedrich Clausen <ftclausen@gmail.com> - Fix Time machine backups
# Reference - http://www.garth.org/archives/2011,08,27,169,fix-time-machine-sparsebundle-nas-based-backup-errors.html


check_args() {
    if (( $# != 1 )); then
        echo "$0 <sparsebundle>"
        cat <<END
where

 * sparebundle - the base name of the sparse bundle

END
        exit 1
    fi
    bundle="$1"

    # Are we in dry run mode?
    if [[ $DRY_RUN != "" ]]; then
        echo "INFO: This is a dry run - showing commands instead of executing them."
        execute="echo"
    fi
}

check_env() {
   if [[ ! -d "$bundle" ]]; then
        echo "Cannot open bundle at $bundle"
        exit 1
    fi

    if (( $(id -u) != 0 )); then
        echo "Run me as root"
        exit 1
    fi
}

rename_bundle() {
    echo "INFO: Running chflags"
    $execute chflags -R nouchg $bundle 
    basename $bundle | egrep --color '_[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+' > /dev/null
    if (( $? == 0 )); then
        echo "INFO: Bundle needs renaming from $bundle"
        clean_bundle=$(echo $bundle | perl -ne 'if($_=~/(_[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+)/){ $_=~s/$1//; print "$_\n";}')
        $execute mv $bundle $clean_bundle
        echo "INFO: Renamed to $clean_bundle"
        bundle=$clean_bundle
    else
        echo "INFO: No rename required."
    fi

}

attach_and_get_device_name() {
    echo "DEBUG: Attaching $bundle..."
    device=$(hdiutil attach -nomount -noverify "$bundle" | egrep Apple_HFSX | awk '{print $1}')
    echo "DEBUG: Using device $device"
}

detach_device() {
    echo "DEBUG: detaching..."
    hdiutil detach $device
}

watch_for_completion() {
    echo -n "INFO: Waiting for disk scan to finish ..."
    while [ 1 ]; do
        tail -4 /var/log/fsck_hfs.log | egrep -i "(FILESYSTEM CLEAN)|(repaired successfully)|(appears to be OK)" > /dev/null 2>&1
        if (( $? == 0 )); then
            echo " filesystem clean/repaired."
            return 0
        fi
        tail -4 /var/log/fsck_hfs.log | egrep -i "not be repaired" > /dev/null 2>&1
        if (( $? == 0 )); then
            echo " filesystem repair failed - please run \`fsck_hfs -drfy $device' and re-run utility."
            return 1
        fi
        sleep 1
    done
}

fix_plist() {
    plist="$bundle/com.apple.TimeMachine.MachineID.plist"
    if [[ ! -f $plist ]]; then
        echo "BUG: Can't open plist at $plist"
        exit 1
    fi
    perl -p -i -e 's/<integer>2<\/integer>/<integer>0<\/integer>/' $plist
    cp $plist $plist.needed_scan.$(date +%s)
    uuid=$(grep -A 1 UUID $plist | tail -n 1 | sed 's/.*<string>\(.*\)<\/string>/\1/')
    date=$(date +%Y-%m-%dT%H:%M:%SZ)
    echo "DEBUG: Disk UUID is $uuid from $plist"
    cat <<END > $plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>VerificationDate</key>
    <date>$date</date>
    <key>VerificationExtendedSkip</key>
    <false/>
    <key>VerificationState</key>
    <integer>0</integer>
    <key>com.apple.backupd.BackupMachineAddress</key>
    <string>00:1b:63:1e:27:87</string>
    <key>com.apple.backupd.HostUUID</key>
    <string>$uuid</string>
</dict>
</plist>
END
}
# Main

check_args $@
check_env
rename_bundle
if [[ $DRY_RUN != "" ]]; then
    echo "INFO: This is as far as I'll go in the dry run"
    exit 0
fi
attach_and_get_device_name
watch_for_completion
if (( $? == 1 )); then
    exit 1
fi
fix_plist
detach_device

