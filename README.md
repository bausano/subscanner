# yt-search

At the moment of writing the app, there is no way to search YouTube video content.

An app which scrapes YouTube subtitles APIs and creates an html file with the transcript. The html files are uploaded to an S3 bucket. The content is indexed by search engines.

It's also a bash practice exercise.

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

## How it works
### Preparing html
```
$ ./gen_html_for_vid.sh ${video_id}
```
* **`video_id`** is the value of `v=` query param in `https://www.youtube.com/watch?v=${video_id}`

---

We use `youtube-dl` to download video information (`${video_id}.info.json`) and subtitles (`${video_id}.en.vtt`).

We read the info and replace placeholders in format `video_${placeholder}_prop` from the `template.html` file.

We parse the subtitles video 3 lines at a time, discarding empty or malformed content. The text with timestamp is stored in a global variable as html `div`. When we're done reading all lines, we replace `video_transcript_prop` in the `template.html` file with the generated html.

We write the output to an html file `${video_id}.html` after minimizing it (~ 50% off) and gzipping it (~ 80% off).

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

## Test videos
There are no tests for the logic so far. If we wanted to make tests, here is a list of videos to use:
* `MBnnXbOM5S4` control example
* `wL7tSgUpy8w` has autogen subtitles but there's only instrumental music
* `3x1b_S6Qp2Q` for benchmarking large videos, autogen subs
* `pTn6Ewhb27k` breaks the "timestamp, text, new line, next" pattern of autogen subtitles
* `ZxYOEwM6Wbk` has weird duplicated subtitles

<!-- Invisible list of references -->
[aws-cli-install]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
