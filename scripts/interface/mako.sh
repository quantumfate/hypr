#!/usr/bin/env bash

DND_MODE="do-not-disturb"
ENABLED=""
DISABLED=""
COUNT_ICON=""

makoctl mode | grep -q "${DND_MODE}"
DND_ACTIVE=$?

COUNT=$(makoctl list 2>/dev/null | grep -c '^Notification [0-9]' || echo)
COUNT=${COUNT:-0}

if [ "$DND_ACTIVE" -eq 0 ]; then
  echo "${DISABLED}"
else
  if [ "$COUNT" -gt 0 ]; then
    echo "${COUNT_ICON} ${COUNT}"
  else
    echo "${ENABLED}"
  fi
fi

