#!/bin/bash
# Unix sucks bad.
set -e
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"

sdir=sessions/`date +"%Y-%m-%dT%H-%M-%S"`
mkdir $sdir
./wslog > $sdir/trajlog.jsons &
./pupil_logger.py |gzip > $sdir/pupil.jsons.gz &

"/mnt/c/pupil_v1.6.11_windows_x64/pupil_capture_windows_x64_v1.6.11/pupil_capture.exe" &
"/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" --allow-file-access-from-files --user-data-dir=chromium-data "file:/C:/Users/TRU/webtrajsim/index.html?disableDefaultLogger=true&experiment=blindPursuit18&wsLogger=ws://localhost:8080&lang=fi"
