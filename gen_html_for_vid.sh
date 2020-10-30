#!/bin/bash
# check for youtube-dl jq
# try long videos
# minimize html/xml

readonly HTML_TEMPLATE_PATH="template.html"
# if N seconds between subtitles then start new paragraph
readonly NEW_LINE_AFTER_PAUSE_S=4

# first arg is famous "?v=" query param
video_id=$1

if [ -z "${video_id}" ]; then
    echo "Video id must be provided. Example: ./gen_html_for_vid MBnnXbOM5S4"
    exit 1
fi

video_url="https://www.youtube.com/watch?v=${video_id}"
info_file_name="${video_id}.info.json"
subs_file_name="${video_id}.en.vtt"

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

    if [[ $? != 0 || -z "${subs_file_name}" ]]; then
        echo "Subtitles for ${video_id} cannot be downloaded."
        exit $?
    fi
}

function subtitles_html_template {
    ## Given seconds into the video, generate timeline and subtitle html.

    local secs=$1
    local text=$2

    # divides total secs to time
    local hours=$(( $secs / 3600 ))
    local rem_secs=$(( $secs - 3600 * $hours ))
    local mins=$(( $rem_secs / 60 ))
    local rem_secs=$(( $rem_secs - 60 * $mins ))

    local hh_mm_ss="$(int_to_time ${hours}):$(int_to_time ${mins}):$(int_to_time ${rem_secs})"

    # FIXME: find more SEO targetted way
    echo "
        <p>
            <a href=\"${video_url}&t=${secs}\" target=\"${video_id}\">
                <time>${hh_mm_ss}</time>
            </a>

            <span>${text}</span>
        </p>
    "
}

function time_to_int {
    ## Converts double digit number such as hours, minutes, seconds.

    local number=$1

    if [[ ${number} = 0* ]]; then
        echo ${number:1}
    else
        echo ${number}
    fi
}

function int_to_time {
    ## Converts integer to double digit number.

    local number=$1

    if [[ (${number} -lt 10) ]]; then
        echo "0${number}"
    else
        echo ${number}
    fi
}

download_video_subtitles

num='[0-9]'
arrow='\s-->\s'

# the html which will be written in a file with subtitles and time stamps
transcript_html_mut=""

# keeps track of when subs ended (?t=)
prev_subs_e_secs=0
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
    if [[ ${timespan} =~ ^($num{2}):($num{2}):($num{2})\.$num{3}$arrow($num{2}):($num{2}):($num{2}) ]]; then
        # when subs start?
        s_hours=$(time_to_int ${BASH_REMATCH[1]})
        s_minutes=$(time_to_int ${BASH_REMATCH[2]})
        s_seconds=$(time_to_int ${BASH_REMATCH[3]})
        s_secs="$(($s_hours * 3600 + $s_minutes * 60 + $s_seconds))"

        # when subs end?
        e_hours=$(time_to_int ${BASH_REMATCH[4]})
        e_minutes=$(time_to_int ${BASH_REMATCH[5]})
        e_seconds=$(time_to_int ${BASH_REMATCH[6]})
        e_secs="$(($e_hours * 3600 + $e_minutes * 60 + $e_seconds))"

        transcript_html_mut+=$(subtitles_html_template ${s_secs} "${text_mut}")

        # add new line if speaker made a pause
        pause_length_s=$(( $s_secs - $prev_subs_e_secs ))
        if [[ $pause_length_s -ge $NEW_LINE_AFTER_PAUSE_S ]]; then
            transcript_html_mut+="<br>"
        fi
        prev_subs_e_secs=$e_secs
    fi
done <<< $(tail -n +5 "${subs_file_name}")

html=$(cat $HTML_TEMPLATE_PATH)

# get info from youtube-dl created json
info_json=$( jq -c '.' "${info_file_name}" )

# replace "video_$PROP_prop" keys with values from info json
properties=( id thumbnail webpage_url uploader title channel_url description )
for prop in "${properties[@]}"
do
    prop_value=$( jq -r -c ".$prop" <<< $info_json )
    html=${html//"video_${prop}_prop"/"${prop_value}"}
done

# build keywords by removing quotes and square brackets from json array
tags=$( jq -r -c ".tags" <<< $info_json | sed 's/\"//g' )
categories=$( jq -r -c ".categories" <<< $info_json | sed 's/\"//g' )
html=${html/video_keywords_prop/"${categories:1:-1},${tags:1:-1}"}

# and finally attach transcript
html=${html/video_transcript_prop/${transcript_html_mut}}

echo $html > "${video_id}.html"

rm
