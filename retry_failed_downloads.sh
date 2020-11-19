#!/bin/bash

source lib.sh

readonly help='
Reads all info json files in the output dir and retries download for each
video id. Then removes the json file regardless if the retry failed or not.

$ ./retry_failed_downloads.sh
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

successes=0
failures=0
for file_name in output/*.info.json; do
    video_id="${file_name:0:$VIDEO_ID_LENGTH}"

    ./gen_vid_page "${video_id}"
    if $?; then
        successes=$(( $successes + 1 ))
        echo "Succesfully generated page for ${video_id}."
    else
        failures=$(( $failures + 1 ))
    fi

    rm "${file_name}"
done

echo "${successes} retries succeeded and ${failures} retries failed."
echo "[`date`] Done!"
