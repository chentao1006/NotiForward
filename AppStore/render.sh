#!/bin/bash
# Renders AppStore/screenshots.html into Mac App Store screenshots at every accepted 16:10 size:
# AppStore/screenshots/<lang>/<width>x<height>/0N.png
{
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for lang in zh en; do
    folder=$([ "$lang" = zh ] && echo zh-Hans || echo en)
    for n in 1 2 3 4 5; do
        master="screenshots/${folder}/2880x1800/0${n}.png"
        mkdir -p "$(dirname "$master")"
        "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
            --window-size=1440,900 --screenshot="$PWD/$master" \
            "file://$PWD/screenshots.html#${lang}-${n}" >/dev/null 2>&1
        for size in 2560x1600 1440x900 1280x800; do
            mkdir -p "screenshots/${folder}/${size}"
            sips -z "${size#*x}" "${size%x*}" "$master" --out "screenshots/${folder}/${size}/0${n}.png" >/dev/null
        done
    done
done
echo "Rendered $(find screenshots -name '*.png' | wc -l | tr -d ' ') screenshots into AppStore/screenshots/"
exit
}
