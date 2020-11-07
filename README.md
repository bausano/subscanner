# yt-search

At the moment of writing the app, there is no way to search YouTube video content.

An app which scrapes YouTube subtitles APIs and creates an html file with the transcript. The html files are uploaded to an S3 bucket. The content is indexed by search engines.

## Dependencies
You must have `youtube-dl` utility installed to fetch the subs and `jq` to query info json file. Then `minify` for html size reduction and `gzip` to serve gzip file to clients. We use `ffmpeg` to convert from `vtt` to `srt` which is much easier to parse.

```
$ apt-get install -y youtube-dl jq minify gzip ffmpeg
```

You must [install AWS CLI][aws-cli-install] and [configure your environment](#publishing-to-web).

```
$ aws --version
aws-cli/2.0.61
```

You might need to grant +x to the bash scripts.

```
$ chmod +x list_channel_vids.sh gen_vid_page.sh upload_pages_to_s3.sh
```

## How it works
### Preparing html
```
$ ./gen_vid_page.sh ${video_id}
```
* **`video_id`** is the value of `v=` query param in `https://www.youtube.com/watch?v=${video_id}`

---

We use `youtube-dl` to download video information (`${video_id}.info.json`) and subtitles (`${video_id}.en.vtt`).

We read the info and replace placeholders in format `video_${placeholder}_prop` from the `template.html` file.

We use `ffmpeg` to convert `vtt` into `srt` which is easier to parse. Each subtitle block starts with an index, next line is always time span and then the content. The text with timestamp is stored in a global variable as html `div`. When we're done reading all lines, we replace `video_transcript_prop` in the `template.html` file with the generated html.

We write the output to an html file `${video_id}.html` after minimizing it (~ 50% off) and gzip-ing it (~ 80% off).

### Publishing to web
```
$ ./upload_pages_to_s3.sh ${bucket}
```
* **`bucket`** is name of AWS S3 bucket to upload the generated html files located in `pages` dir to

---

We use AWS CLI to sync `pages` directory with provided S3 bucket name. The S3 is then configured as a static website and is published to the web via Cloudfront.

To upload to S3 credentials must be provided. There are several options:
* run `aws configure` and then the script - the CLI will pick up your profile;
* copy `.env.example` into `.env` file and use your credentials;
* `export` necessary environment variables before running the script.

Updating static files like the `style.css`, `index.html` and `error.html` is currently manual. Since these files won't change very often automation is not an attractive option.

### Persistence
Should we want to access list of all videos we've scraped, we can list the objects in the S3 bucket. However this level of granularity is not necessary. Instead, we use [sitemap][sitemap] to store which channels have we scraped and when. A site map links to a channel html which lists links to videos.

We leverage the `<lastmod>` tag to remember the last time we scraped the channel. A script then visits the sitemap file and searches for channels which haven't been scraped in D days. We then run a script which returns list of ids of videos which have been uploaded since the last time we scraped (or maybe last time we scraped minus some delay to fetch imminent subtitle improvements and fail safe).

A sitemap xml file is gzip-ped and uploaded to the S3 bucket. A single sitemap can have at most 50k urls. Each next 50k scraped channels are stored in new sitemap. The [`sitemap_index.xml`](static/sitemap_index.xml) file keeps track of all the sitemap files created so far. Addition to the index are done manually for this being so infrequent event automation doesn't make sense so far.

## Test videos
There are no tests for the logic so far. If we wanted to make tests, here is a list of videos to use:
* `MBnnXbOM5S4` control example
* `wL7tSgUpy8w` has autogen subtitles but there's only instrumental music
* `3x1b_S6Qp2Q` for benchmarking large videos, autogen subs
* `pTn6Ewhb27k` breaks the "timestamp, text, new line, next" pattern of autogen subtitles
* `ZxYOEwM6Wbk` has weird duplicated subtitles

<!-- Invisible list of references -->
[aws-cli-install]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
[sitemap]: https://www.sitemaps.org/protocol.html
