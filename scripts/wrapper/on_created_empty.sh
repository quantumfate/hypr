#!/usr/bin/env bash
APP=$1
# Wrapper script for race conditions where windows would open before a special workspace is rendered
sleep 1
hyprctl dispatch exec [workspace special:$APP] $APP

