#!/bin/bash

source lib.sh

readonly help='
Reads all info json files in the tmp dir and retries download for each
video id. Then removes the json file regardless if the retry failed or not.

$ ./retry_failed_downloads.sh [--max-concurrent 4]
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

max_concurrent=4
for key in "$@"; do
    case ${key} in
        --max-concurrent)
        max_concurrent=$2
        ;;
    esac
    # go to next flag
    shift
done

# counters for info printing
successes_mut=0
failures_mut=0

function retry_gen_vid {
    ## Given video info json filename, retries the download and in any case
    ## removes the file.

    local filename=$1

    # skip output path and slash in file name
    local from_char=$(( ${#OUTPUT_PATH} + 1 ))
    local video_id="${file_name:$from_char:$VIDEO_ID_LENGTH}"

    ./gen_vid_page.sh "${video_id}"
    if [[ $? == 0 ]]; then
        successes_mut=$(( $successes_mut + 1 ))
        echo "Succesfully generated page for ${video_id}."
    else
        failures_mut=$(( $failures_mut + 1 ))
        rm "${file_name}"
    fi
}

for file_name in $OUTPUT_PATH/*.info.json; do
    # limit number of running jobs
    while [ `jobs | grep "Running" -c` -ge $max_concurrent ]
    do
        sleep 1
    done

    # runs gen function in background
    retry_gen_vid "${video_id}" &
done

echo "${successes_mut} retries succeeded and ${failures_mut} retries failed."
echo "[`date`] Done!"
