`gen_vid_page.sh` stores subtitles and video metadata in this folder (downloaded with `youtube-dl`). When we successfully parse the subs and store them in `../pages` directory, we delete the created files. However if `gen_vid_page.sh` fails it will leave a `${video_id}.info.json` metadata file in this dir.

We leverage that behavior by reading all remaining metadata files names and retrying to download subs one more time. After we've retried to download all those videos again, we purge the contents of this dir.
