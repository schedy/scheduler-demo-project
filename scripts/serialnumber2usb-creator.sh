#!/bin/bash

for J in $(seq -f '%03g' 0 30); do
    for I in $(seq -f '%03g' 0 130); do
        USBPATH=/dev/bus/usb/$J/$I
        SEGGER_SN=$(udevadm info $USBPATH 2>/dev/null | grep 'ID_SERIAL=SEGGER_J-Link_' | sed 's/^E: ID_SERIAL=SEGGER_J-Link_//')
        if [[ -n ${SEGGER_SN} ]]; then
            echo "${SEGGER_SN};${USBPATH}"
        fi
    done
done

# vim:set softtabstop=4 shiftwidth=4 tabstop=4 expandtab:
