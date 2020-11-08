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

# https://stackoverflow.com/questions/6180138/whats-the-maximum-length-of-a-youtube-video-id
readonly VIDEO_ID_LENGTH=11

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

# takes a while
# FIXME(https://github.com/bausano/yt-search/issues/9)
if [ -n "${since}" ]; then
    echo "[$(date)] Scanning videos since ${since}..."
    since_no_dash="${since//-/}"
    ids=$( youtube-dl --get-id --dateafter "${since_no_dash}" "${channel_url}" )
else
    echo "[$(date)] Scanning all videos..."
    ids=$( youtube-dl --get-id "${channel_url}" )
fi
abort_on_err $? "Cannot get channel video ids"

echo "[$(date)] Downloading subs for following vids:"
echo "${ids}"
while read video_id;
do
    if [[ ! ${#video_id} -eq ${VIDEO_ID_LENGTH} ]]; then
        continue
    fi

    # limit number of running jobs
    while [ `jobs | wc -l | xargs` -ge $max_concurrent ]
    do
        sleep 1
    done

    # in background and prepend stdout with vid id
    # FIXME(https://github.com/bausano/yt-search/issues/13)
    ./gen_vid_page.sh "${video_id}" | sed 's/^/['"${video_id}"'] /' &
done <<< "${ids}"

# await all jobs
for job in `jobs -p`; do wait ${job}; done

echo "[$(date)] Done!"
