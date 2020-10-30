#!/bin/bash
# check for youtube-dl jq
# try long videos
# minimize html/xml

# first arg is famous "?v=" query param
video_id=$1

if [ -z "${video_id}" ]; then
    echo "Video id must be provided. Example: ./gen_html_for_vid MBnnXbOM5S4"
    exit 1
fi

# TODO: check valid input

HTML_TEMPLATE_PATH="template.html"
video_url="https://www.youtube.com/watch?v=${video_id}"

function download_video_subtitles {
    ## Given video id downloads subtitles to disk and returns path to the file.

    function youtube_dl {
        ## Runs youtube-dl to get subtitles. Can be parametrized to get auto
        ## or manmade subs.

        # Can be either "--write-sub" or "--write-auto-sub".
        local sub_flag=$1

        local stdout_success_msg="Writing video subtitles"

        # --id stores file with video id in name
        # --write-info-json creates a new json file with video metadata which
        #                   we use to get title, tags, description, ...
        result_download_sub=$(youtube-dl --id --write-info-json --skip-download --sub-lang en "${sub_flag}" "${video_url}")
        if [[ "${result_download_sub}" == *"${stdout_success_msg}"* ]]; then
            return 0
        fi

        return 1
    }

    # attempt download manmade subs or fallback to auto subs
    youtube_dl --write-sub || youtube_dl --write-auto-sub

    # print file name on success
    if [[ $? == 0 ]]; then
        echo "${video_id}.en.vtt"
    fi

    return $?
}

function timeline_html_template {
    echo "
        <a href=\"${video_url}&t=${start_at_time_sec}\" target=\"${video_id}\">
            <time>${start_at_time}</time>
        </a>
    "
}

function subtitles_html_template {
    ## Given timeline when subtitle appears and subtitle text, return html.

    local hours=$2 local minutes=$3 local seconds=$4
    local text=$5

    local start_at_time="$(from_integer_to_double_digit ${hours}):$(from_integer_to_double_digit ${minutes}):$(from_integer_to_double_digit ${seconds})"
    # query param "&t" is in secs
    local start_at_time_sec="$(($hours * 3600 + $minutes * 60 + $seconds))"

    echo "<a href=\"${video_url}&t=${start_at_time_sec}\" target=\"${video_id}\">
    <time>${start_at_time}</time>
    <p>${text}</p>
</a>
"
}

function from_double_digit_to_integer {
    ## Converts double digit number such as hours, minutes, seconds.

    local number=$1

    if [[ ${number} = 0* ]]; then
        echo ${number:1}
    else
        echo ${number}
    fi
}

function from_integer_to_double_digit {
    ## Converts integer to double digit number.

    local number=$1

    if [[ (${number} -lt 10) ]]; then
        echo "0${number}"
    else
        echo ${number}
    fi
}

function exit_on_err_with {
    ## Given message, prints it and dies if last command failed.

    local message=$1

    if [[ $? != 0 ]]; then
        echo message
        exit 1
    fi
}

sub_file_name=$(download_video_subtitles "${video_id}")
exit_on_err_with "Subtitles for ${video_id} cannot be downloaded."

num='[0-9]'
arrow='\s-->'

# the html which will be written in a file with subtitles and time stamps
transcript_html_mut=""

# read 3 lines at once, first one has time info, second the subtitle text, third
# is always empty.
while read -r timespan; do
    read -r text_mut
    read -r _new_line

    # TODO: remove all string between []

    # FIXME: bench fastest method at https://linuxhint.com/trim_string_bash/
    text_mut="${text_mut##*( )}"
    text_mut="${text_mut%%*( )}"

    if [ -z "${text_mut}" ]; then
        continue
    fi

    # # FIXME: build regex up front
    if [[ ${timespan} =~ ^($num{2}):($num{2}):($num{2})\.$num{3}$arrow ]]; then
        hours=$(from_double_digit_to_integer ${BASH_REMATCH[1]})
        minutes=$(from_double_digit_to_integer ${BASH_REMATCH[2]})
        seconds=$(from_double_digit_to_integer ${BASH_REMATCH[3]})

        transcript_html_mut+=$(subtitles_html_template ${video_id} ${hours} ${minutes} ${seconds} "${text_mut}")
    fi
done <<< $(tail -n +5 "${sub_file_name}")

html=$(cat $HTML_TEMPLATE_PATH)

# get info from youtube-dl created json
info_json=$( jq -c '.' "${video_id}.info.json" )
properties=( id thumbnail webpage_url uploader title channel_url description )
for prop in "${properties[@]}"
do
    prop_value=$( jq -r -c ".$prop" <<< $info_json )
    html=${html//"video_${prop}_prop"/"${prop_value}"}
done

tags=$( jq -r -c ".tags" <<< $info_json | sed 's/\"//g' )
categories=$( jq -r -c ".categories" <<< $info_json | sed 's/\"//g' )
html=${html/video_keywords_prop/"${categories:1:-1},${tags:1:-1}"}

html=${html/video_transcript_prop/${transcript_html_mut}}

echo $html > "${video_id}.html"
