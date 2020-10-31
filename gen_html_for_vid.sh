#!/bin/bash

# Downloads video subtitles from YouTube with youtube-dl and formats them into
# html. Uses template.html file to replace placeholders and stores the result in
# another html file.

if ! command -v youtube-dl &> /dev/null
then
    echo "youtube-dl is missing\n sudo apt-get install youtube-dl" && exit 1
fi

if ! command -v jq &> /dev/null
then
    echo "jq is missing\n sudo apt-get install jq" && exit 1
fi

readonly HTML_TEMPLATE_PATH="template.html"
# if N seconds between subtitles then start new paragraph
readonly NEW_LINE_AFTER_PAUSE_S=4
# "11:22:33.938 --> 44:55:66" matches position "nn" in nth group for 6 groups
readonly D="[[:digit:]]"
readonly MATCH_TIMESPAN="^($D{2}):($D{2}):($D{2})\.$D{3}\s-->\s($D{2}):($D{2}):($D{2})"

# first arg is famous "?v=" query param
readonly video_id=$1

if [ -z "${video_id}" ]; then
    echo "Video id must be provided. Example: ./gen_html_for_vid MBnnXbOM5S4"
    exit 1
fi

readonly video_url="https://www.youtube.com/watch?v=${video_id}"
readonly info_file_name="${video_id}.info.json"
readonly subs_file_name="${video_id}.en.vtt"

# will be stored as a file
html_mut=$(cat $HTML_TEMPLATE_PATH)
# html to replace template's transcript placeholder with paht
transcript_mut=""

function download_video_subtitles {
    ## Given video id downloads subtitles to disk and returns path to the file.
    echo "[$(date)] Downloading subs..."

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

    # attempt download subs
    # option to download auto subs is disabled as quality is low
    youtube_dl --write-sub || youtube_dl --write-auto-sub

    if [[ $? != 0 || -z "${subs_file_name}" ]]; then
        echo "Subtitles for ${video_id} cannot be downloaded."
        exit $?
    fi
}

function parse_subtitles_file {
    ## Loads and parses subs, puts results into html. This function mutates
    ## parameter "html_mut".
    echo "[$(date)] Parsing subs file..."

    # keeps track of when subs ended (?t=)
    local prev_subs_ended_at_sec=0

    function time_to_int {
        ## Converts double digit number such as hours, minutes, seconds.

        local number=$1

        if [[ ${number} = 0* ]]; then
            return ${number:1}
        else
            return ${number}
        fi
    }

    function subtitles_html_template {
        ## Given seconds into the video and timestamp, generate timeline and
        ## subtitle html.

        local appear_at_sec=$1
        local hh_mm_ss=$2
        local text=$3

        # FIXME: find more SEO targetted way
        transcript_mut+="
            <div class=\"subtitle\">
                <div>
                    <a href=\"${video_url}&t=${appear_at_sec}\" target=\"${video_id}\">
                        <time>${hh_mm_ss}</time></a>
                </div>
                <div>
                    <span>${text}</span>
                </div>
            </div>
        "
    }

    # read 3 lines at once, first one has time info, second the subtitle text, third
    # is always empty.
    while read -r timespan; do
        read -r text_mut
        read -r _new_line

        # TODO: remove all string between [ and ]

        # trim spaces
        text_mut="${text_mut##*( )}"
        text_mut="${text_mut%%*( )}"

        if [ -z "${text_mut}" ]; then
            continue
        fi

        if [[ ${timespan} =~ $MATCH_TIMESPAN ]]; then
            # when subs start?
            s_hh="${BASH_REMATCH[1]}"
            s_mm="${BASH_REMATCH[2]}"
            s_ss="${BASH_REMATCH[3]}"
            s_hh_mm_ss="${s_hh}:${s_mm}:${s_ss}"
            time_to_int ${s_hh}; s_hours=$?
            time_to_int ${s_mm}; s_minutes=$?
            time_to_int ${s_ss}; s_seconds=$?
            curr_subs_appeared_at_sec="$(($s_hours * 3600 + $s_minutes * 60 + $s_seconds))"

            # add new line if there was pause
            pause_length_s=$(( $curr_subs_appeared_at_sec - $prev_subs_ended_at_sec ))
            if [[ $pause_length_s -ge $NEW_LINE_AFTER_PAUSE_S ]]; then
                transcript_mut+="<br>"
            fi

            subtitles_html_template ${curr_subs_appeared_at_sec} ${s_hh_mm_ss} "${text_mut}"

            # when subs end?
            time_to_int ${BASH_REMATCH[4]}; e_hours=$?
            time_to_int ${BASH_REMATCH[5]}; e_minutes=$?
            time_to_int ${BASH_REMATCH[6]}; e_seconds=$?
            prev_subs_ended_at_sec="$(($e_hours * 3600 + $e_minutes * 60 + $e_seconds))"
        fi
    done <<< $(tail -n +5 "${subs_file_name}")

    # and finally attach transcript to the html
    html_mut=${html_mut/video_transcript_prop/${transcript_mut}}
}

function replace_template_placeholders {
    ## Gets info from metadata file and replaces placeholders in "html_mut".
    echo "[$(date)] Replacing template placeholders..."

    # get info from youtube-dl created json
    local info_json=$( jq -c '.' "${info_file_name}" )

    # replace "video_$PROP_prop" keys with values from info json
    local properties=(
        id title thumbnail webpage_url
        uploader channel_url
    )
    for prop in "${properties[@]}"
    do
        prop_value=$( jq -r -c ".$prop" <<< $info_json )
        html_mut=${html_mut//"video_${prop}_prop"/"${prop_value}"}
    done

    # build keywords by removing quotes and square brackets from json array
    local tags=$( jq -r -c ".tags" <<< $info_json | sed 's/\"//g' )
    local categories=$( jq -r -c ".categories" <<< $info_json | sed 's/\"//g' )
    html_mut=${html_mut/video_keywords_prop/"${categories:1:-1},${tags:1:-1}"}
}

download_video_subtitles # (and meta info) to disk
replace_template_placeholders # with values from meta info json file
parse_subtitles_file # and store results in "html_mut"
echo $html_mut > "pages/${video_id}.html"

# delete temp downloads
rm -rf "${info_file_name}" "${subs_file_name}"

echo "[$(date)] Done!"
