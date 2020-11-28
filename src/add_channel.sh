#!/bin/bash

source lib.sh

readonly help='
Generates pages for all channel vids and adds channel to db.
* env var DB_NAME
* channel id as given by yt (/channel/${channel_id} and not /c/${channel_name})
* optinal `--max-concurrent integer` flag which limits how many videos are
    processed at once

$ ./add_channel.sh ${channel_id} [--max-concurrent 4]
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

check_dependency "aws"

# Imports the .env file environment variables if present.
if test -f "${ENV_FILE_PATH}"; then
    echo "(source ${ENV_FILE_PATH})"
    source ${ENV_FILE_PATH}
fi

# youtube.com/channel/${channel_id}
readonly channel_id=$1
if [ -z "${channel_id}" ]; then
    echo "Channel id must be provided. See ./add_channel help"
    exit 1
fi

max_concurrent=${MAX_CONCURRENT}
for key in "$@"; do
    case ${key} in
        --max-concurrent)
        max_concurrent=$2
        ;;
    esac
    # go to next flag
    shift
done

if [ -z "${DB_NAME}" ]; then
    echo "DynamoDB name env var must be provided. See ./add_channel help"
    exit 1
fi

# get it from ddb, if exists exit 1
already_exists=$(aws dynamodb get-item --table-name "${DB_NAME}" \
    --key "{\"channel_id\": {\"S\": \"${channel_id}\"}}" \
    | grep "${channel_id}" -c)

if [ $already_exists -eq 1 ]; then
    echo "Channel ${channel_id} already exists."
    exit 1
fi

function add_channel_to_db {
    ## Inserts channel id to db.

    local updated_at=$1

    echo "[`date`] Inserting channel to db..."
    aws dynamodb put-item \
        --table-name "${DB_NAME}" \
        --item "{
            \"channel_id\": {\"S\": \"${channel_id}\"},
            \"updated_at\": {\"N\": \"${updated_at}\"}
        }"
    abort_on_err $? "Cannot store channel in db."
}

# scrape all vids to date
echo "[`date`] Scraping channel videos..."
./gen_channel_vids_pages.sh "${channel_id}" --max-concurrent "${max_concurrent}"
res=$?

if [[ $res == 0 ]]; then
    add_channel_to_db "$(date +%s)"
    echo "[`date`] Done!"
elif [[ ?res == $ERR_TRY_LATER ]]; then
    echo "Too many requets. Try channel ${channel_id} later."
    # we add the channel, but set the time to 0, so next time we will query all
    # channels from scratch
    add_channel_to_db "0"
    exit $ERR_TRY_LATER
else
    echo "Error downloading channel ${channel_id}."
    exit 1
fi
