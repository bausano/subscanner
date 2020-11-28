#!/bin/bash

source lib.sh

readonly help='
Polls sqs messages with channel ids. For each message it reads, it starts the
procedure for adding channel. Every N messages it uploads all scraped pages to
S3. Every M messages it retries downloading failed videos.
* env var SQS_URL
* flag `--sitemap` with the name of the sitemap file stored in S3 to append new
    videos to (if the file does not exist we create new one)
* optional `--upload-after N` flag which says how many channels to process
    before uploading scraped vids to S3. Defaults to 10.
* option `--retry-failed-after M` flag which says how many channels to process
    before retrying all failed videos. If not provided, retry procedure is not
    ran.

$ ./listen_to_sqs.sh --sitemap "sitemap1.xml" \
    [--upload-after 10] \
    [--retry-failed-after M]
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

check_dependency "aws"

# Imports the .env file environment variables if present.
if test -f "${ENV_FILE_PATH}"; then
    echo "(source ${ENV_FILE_PATH})"
    source ${ENV_FILE_PATH}
fi

upload_after=10
for key in "$@"; do
    case ${key} in
        --upload-after)
        upload_after=$2
        ;;
        --retry-failed-after)
        readonly retry_failed_after=$2
        ;;
        --sitemap)
        readonly sitemap_file=$2
        ;;
    esac
    # go to next flag
    shift
done

if [ -z "${sitemap_file}" ]; then
    echo "Sitemap file must be provided. See ./listen_to_sqs help"
    exit 1
fi

if [ -z "${SQS_URL}" ]; then
    echo "SQS_URL env must be provided. See ./listen_to_sqs help"
    exit 1
fi

downloaded_count=0

echo "Listening to messages from SQS '${SQS_URL}'."
while true;
do
    message=$(aws sqs receive-message \
        --queue-url "${SQS_URL}" \
        --wait-time-seconds 20 \
        | jq -r '.Messages | .[] | .ReceiptHandle, .Body')
    readarray -t message_props <<< "${message}"

    if [ ${#message_props[@]} -ne 2 ];
    then
        continue
    fi

    echo "Received new message."

    message_handle="${message_props[0]}"
    aws sqs delete-message --queue-url "${SQS_URL}" --receipt-handle "${message_handle}"

    message_body="${message_props[1]}"

    # https://webapps.stackexchange.com/a/101153
    CHANNEL_ID_REGEX="([0-9A-Za-z_-]{23}[AQgw])"
    if [[ ! ${message_body} =~ $CHANNEL_ID_REGEX ]]; then
        continue
    fi

    channel_id="${BASH_REMATCH[1]}"
    echo "Sleeping for 1m to avoid getting banned by youtube."
    sleep 60
    echo "Adding channel ${channel_id}..."
    ./add_channel.sh "${channel_id}"
    res=$?

    if [[ $res == $ERR_TRY_LATER ]]; then
        echo "This IP got banned :("
        ./upload_pages_to_s3.sh --sitemap "${sitemap_file}"
        # kill the script if we got banned by yt
        exit $ERR_TRY_LATER
    elif [[ $res != 0  ]]; then
        continue
    fi

    downloaded_count=$(( $downloaded_count + 1 ))

    # if it's time to upload pages, push to s3
    if [ $(( $downloaded_count % $upload_after )) -eq 0 ];
    then
        ./upload_pages_to_s3.sh --sitemap "${sitemap_file}"
    fi

    # if --retry-failed-after is set and it's time to retry
    if [ ! -z "${retry_failed_after}" ] &&
        [ $(( $downloaded_count % $retry_failed_after )) -eq 0 ]; then
        ./retry_failed_downloads.sh
    fi
done
