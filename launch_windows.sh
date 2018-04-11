#!/bin/bash
# Unix sucks bad.
trap 'kill -HUP 0' EXIT

cd "$( dirname "${BASH_SOURCE[0]}" )"

sdir=sessions/`date -Isecond |base64`
mkdir $sdir
./wslog > $sdir/trajlog.jsons &

"/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" --allow-file-access-from-files --user-data-dir=chromium-data "file:/C:/Users/TRU/webtrajsim/index.html?disableDefaultLogger=true&experiment=blindPursuit18&wsLogger=ws://localhost:8080&targetSize=0.5"
