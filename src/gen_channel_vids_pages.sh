#!/bin/bash

source lib.sh

readonly help='
Lists youtube video ids from given channel. Then it call `gen_vid_page.sh`
for each video.
* channel id as given by yt (/channel/${channel_id} and not /c/${channel_name})
* optinal `--since {yyyy-mm-dd}` flag
* optinal `--max-concurrent integer` flag which limits how many videos are
    processed at once

Adds channel into db and generates pages, but you need to publish those pages
with `upload_pages_to_s3.sh`.

$ ./gen_channel_vids_pages.sh ${channel_id} \
    [--since "yyyy-mm-dd"] \
    [--max-concurrent 4]
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

check_dependency "youtube-dl"

# youtube.com/channel/${channel_id}
readonly channel_id=$1
if [ -z "${channel_id}" ]; then
    echo "Channel id must be provided. See ./gen_channel_vids_pages help"
    exit 1
fi

readonly channel_url="https://www.youtube.com/channel/${channel_id}"

max_concurrent=4
for key in "$@"; do
    case ${key} in
        --since)
        since=$2
        ;;
        --max-concurrent)
        max_concurrent=$2
        ;;
    esac
    # go to next flag
    shift
done

# prepares cmd to execute which pulls channel videos and prints them line after
# line
if [ -n "${since}" ]; then
    echo "[`date`] Scanning videos since ${since}..."
    since_no_dash="${since//-/}"
    channel_vids_stream="youtube-dl --get-id --dateafter ${since_no_dash} ${channel_url}"
else
    echo "[`date`] Scanning all videos..."
    channel_vids_stream="youtube-dl --get-id ${channel_url}"
fi

# to speed up the process we process video as soon as the id is fetched by
# youtube-dl instead of waiting for the fetching process to finish
eval "$channel_vids_stream" \
| while read -r video_id; do
    if [[ ! ${#video_id} -eq ${VIDEO_ID_LENGTH} ]]; then
        continue
    fi

    # limit number of running jobs
    while [ `jobs | grep "Running" -c` -ge $max_concurrent ];
    do
        sleep 1
    done

    # in background and prepend stdout with vid id
    ./gen_vid_page.sh "${video_id}" | sed 's/^/['"${video_id}"'] /' &
done
abort_on_err $? "Videos for channel ${channel_id} cannot be created."

# await all jobs
for job in `jobs -p`; do wait ${job}; done

echo "[`date`] Done!"
