#!/bin/bash

### Library with helper functions.

# https://stackoverflow.com/questions/6180138/whats-the-maximum-length-of-a-youtube-video-id
export VIDEO_ID_LENGTH=11
# directory where to write output files from youtube-dl
export OUTPUT_PATH="tmp"
# directory where we store generated html pages
readonly PAGES_DIR_TO_SYNC="pages"

function check_dependency {
    ## Checks that dependency is installed, otherwise exits.

    local dep=$1

    if command -v $dep &> /dev/null
    then
        return 0
    fi

    echo "'${dep}' dependency missing"

    if [ "${dep}" == "aws" ];
    then
        echo "Follow the official guide at"
        echo "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
    else
        echo "\$ sudo apt-get install ${dep}"
    fi

    exit 1
}

function abort_on_err {
    ## If last command failed print err message and exit.

    local status=$1
    local err_msg=$2

    if [[ $status != 0 ]]; then
        echo "[`date`] ERR $status: ${err_msg}"
        exit $status
    fi
}
