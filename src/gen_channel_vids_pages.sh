#!/bin/bash

source lib.sh

readonly help='
Lists youtube video ids from given channel. Then it call `gen_vid_page.sh`
for each video.
* channel id as given by yt (/channel/${channel_id} and not /c/${channel_name})
* optinal `--since {yyyy-mm-dd}` flag

Adds channel into db and generates pages, but you need to publish those pages
with `upload_pages_to_s3.sh`.

$ ./gen_channel_vids_pages.sh ${channel_id} \
    [--since "yyyy-mm-dd"] \
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

for key in "$@"; do
    case ${key} in
        --since)
        since=$2
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
# we redirect stderr to stdout so that we can catch errors
eval "$channel_vids_stream" 2>&1 \
| while read -r line; do
    if [[ ! ${#line} -eq ${VIDEO_ID_LENGTH} ]]; then
        if [[ "${line}" =~ "${HTTP_429}" ]]; then
            echo "${HTTP_429}"
            exit $ERR_TRY_LATER
        fi
        continue
    fi

    video_id=$line

    ./gen_vid_page.sh "${video_id}" | sed 's/^/['"${video_id}"'] /'
    echo "Sleeping for 10s after vid download."
    sleep 10
done

echo "[`date`] Done!"
