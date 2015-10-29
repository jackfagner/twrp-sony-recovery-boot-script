#!/bootrec/busybox sh

########################################
# Sony FOTAKernel Recovery Boot Script #
#    Author: github.com/jackfagner     #
#             Version: 1.1             #
########################################

# Disable printing/echo of commands
set +x

############
# SETTINGS #
############

REAL_INIT="/init.real"

DEV_FOTA_NODE="/dev/block/mmcblk0p32 b 259 0"
DEV_FOTA="/dev/block/mmcblk0p32"
DEV_EVENT_NODE="/dev/input/event5 c 13 69"
DEV_EVENT="/dev/input/event5"

LOG_FILE="/bootrec/boot-log.txt"
KEYLOG_FILE="/bootrec/boot-key-events.txt"
RECOVERY_CPIO="/bootrec/recovery.cpio"

KEY_EVENT_DELAY=3
WARMBOOT_RECOVERY=0x77665502
MIN_KEY_EVENT_DATA_LENGTH=32

LED_RED="/sys/class/leds/led:rgb_red/brightness"
LED_GREEN="/sys/class/leds/led:rgb_green/brightness"
LED_BLUE="/sys/class/leds/led:rgb_blue/brightness"


############
#   CODE   #
############

# Save current PATH variable, then change it
_PATH="$PATH"
export PATH=/bootrec:/sbin

# Use root as base dir
busybox cd /

# Log current date/time
busybox date >> ${LOG_FILE}

# Redirect stdout and stderr to log file
exec >> ${LOG_FILE} 2>&1

# Re-enable printing commands
set -x

# Delete this script
busybox rm -f /init

# Create directories
busybox mkdir -m 755 -p /dev/input
busybox mkdir -m 555 -p /proc
busybox mkdir -m 755 -p /sys

# Create device nodes
busybox mknod -m 600 ${DEV_EVENT_NODE}
busybox mknod -m 666 /dev/null c 1 3

# Mount filesystems
busybox mount -t proc proc /proc
busybox mount -t sysfs sysfs /sys

# Methods for controlling LED
led_amber() {
  busybox echo 255 > ${LED_RED}
  busybox echo 255 > ${LED_GREEN}
  busybox echo   0 > ${LED_BLUE}
}
led_orange() {
  busybox echo 255 > ${LED_RED}
  busybox echo 100 > ${LED_GREEN}
  busybox echo   0 > ${LED_BLUE}
}
led_off() {
  busybox echo   0 > ${LED_RED}
  busybox echo   0 > ${LED_GREEN}
  busybox echo   0 > ${LED_BLUE}
}

# Start listening for key events
busybox cat ${DEV_EVENT} > ${KEYLOG_FILE} &

# Set LED to amber to indicate it's time to press keys
led_amber

# Sleep for a while to collect key events
busybox sleep ${KEY_EVENT_DELAY}

# Data collected, kill key event collector
busybox pkill -f "cat ${DEV_EVENT}"

# Count collected data length
KEY_EVENT_DATA_LENGTH=`busybox wc -c <${KEYLOG_FILE}`

# Check if we collected enough key event data or the user rebooted into recovery mode
if [ ${KEY_EVENT_DATA_LENGTH} -gt ${MIN_KEY_EVENT_DATA_LENGTH} ] || busybox grep -q warmboot=${WARMBOOT_RECOVERY} /proc/cmdline; then
  echo "Entering Recovery Mode" >> ${LOG_FILE}

  # Set LED to orange to indicate recovery mode
  led_orange

  # Create directory and device node for FOTA partition
  busybox mkdir -m 755 -p /dev/block
  busybox mknod -m 600 ${DEV_FOTA_NODE}

  # Make sure root is in read-write mode
  busybox mount -o remount,rw /

  # extract_elf_ramdisk needs sh in PATH, so let's make sure it is there
  busybox test ! -e /sbin/sh && CREATE_SH=1
  busybox test "${CREATE_SH}" && busybox ln -sf /sbin/busybox /sbin/sh

  # Extract recovery ramdisk
  extract_elf_ramdisk -i ${DEV_FOTA} -o ${RECOVERY_CPIO} -t /

  # Remove sh again (if we created it)
  busybox test "${CREATE_SH}" && busybox rm -f /sbin/sh

  # Clean up rc scripts in root to avoid problems
  busybox rm -f /init*.rc /init*.sh

  # Unpack ramdisk to root
  busybox cpio -i -u < ${RECOVERY_CPIO}

  # Delete recovery ramdisk
  busybox rm -f ${RECOVERY_CPIO}
else
  echo "Booting Normally" >> ${LOG_FILE}

  # Move real init script into position
  busybox mv ${REAL_INIT} /init
fi

# Clean up, start with turning LED off
led_off

# Remove folders and devices
busybox umount /proc
busybox umount /sys
busybox rm -rf /dev/*

# Set permissions to avoid security problems
busybox chmod 644 ${LOG_FILE} ${KEYLOG_FILE}

# Remove dangerous files to avoid security problems
busybox rm -f /bootrec/extract_elf_ramdisk /bootrec/init.sh /bootrec/busybox

# Reset PATH
export PATH="${_PATH}"

# All done, now boot
exec /init
