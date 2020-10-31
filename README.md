# yt-search

At the moment of writing the app, there is no way to search YouTube video content.

An app which scrapes YouTube subtitles APIs and creates an html file with the transcript. The html files are uploaded to an S3 bucket. The content is indexed by search engines.

## How it works
We use `youtube-dl` to download video information (`${video_id}.info.json`) and subtitles (`${video_id}.en.vtt`).

We read the info and replace placeholders in format `video_${placeholder}_prop` from the `template.html` file.

We parse the subtitles video 3 lines at a time, discarding empty or malformed content. The text with timestamp is stored in a global variable as html `div`. When we're done reading all lines, we replace `video_transcript_prop` in the `template.html` file with the generated html.

We write the output to an html file `${video_id}.html`.

## How to run

```
$ ./gen_html_for_vid.sh ${video_id}
```

where `video_id` is the value of `v=` query param in `https://www.youtube.com/watch?v=${video_id}`.

## TODO
- list all video ids from channel
- sam template to create necessary resources on aws
- script to upload html file
- database of last time we scraped all videos from a channel which helps avoid re-scraping videos
- minify and gzip html files when serving them
- google adwords

## Test videos
There are no tests for the logic so far. If we wanted to make tests, here is a list of videos to use:
- `MBnnXbOM5S4` control example
- `wL7tSgUpy8w` has auto generated subtitles but there's only instrumental music
- `3x1b_S6Qp2Q` for benchmarking large videos, auto generated subs
