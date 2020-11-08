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
Each script accepts `help` as first argument, in which case it will print its documentation and exit.

### Persistence

```
$ ./add_channel.sh ${channel_id} --db ${ddb_name} [--max-concurrency 4]
```
* **`channel_id`** is id of youtube channel as found in `youtube.com/channel/${channel_od}` (NOT the channel name in `youtube.com/c/${channel_name}`)
* **`--db`** flag is for name of AWS DynamoDB table which stores timestamp of channel last scape
* **`--max-concurrency`** flag is for how many videos to download at once (default 4)

---

In [DynamoDB table][aws-cli-dynamodb] we store `channel_id` as string primary key and each row has associated `updated_at` number value (unix timestamp). Every time we revisit channel to scrape new videos, we update the `updated_at` value in db.

The `add_channel.sh` script is used to add new entries to db. It will scrape all videos to date and store them in `pages` directory.

Should we want to access list of all videos we've scraped, we can list the objects in the S3 bucket. However this level of granularity is not necessary.

### Publishing to web
```
$ ./upload_pages_to_s3.sh ${bucket} --domain ${domain_name} --sitemap ${sitemap_file_name_on_s3}
```
* **`bucket`** is name of AWS S3 bucket to upload the generated html files located in `pages` dir to
* **`--domain`** flag is for the name of the domain to create URLs for in sitemap
* **`--sitemap`** flag is for the name of the xml file in S3 which will be appended new page URLs (if the file doesn't exist, new is created from sitemap template)

---

We use AWS CLI to sync `pages` directory with provided S3 bucket name. The S3 is then configured as a static website and is published to the web via Cloudfront.

We append links to new videos to a [sitemap][sitemap]. The sitemap is downloaded from S3, appended and uploaded back to the S3 bucket. If the file doesn't exist, new one is created. Provide the name of the file with `--sitemap` flag. This is useful for parallel scraping where each process only operates on its own sitemap file thus avoiding data races.

The [`sitemap_index.xml`](static/sitemap_index.xml) file keeps track of all the sitemap files created so far. New additions are manual.

To upload to S3 credentials must be provided. There are several options:
* run `aws configure` and then the script - the CLI will pick up your profile;
* copy `.env.example` into `.env` file and use your credentials;
* `export` necessary environment variables before running the script.

Updating static files like the `style.css`, `index.html` or `error.html` is currently manual. Since these files won't change very often automation is not an attractive option.

### Preparing html
```
$ ./gen_vid_page.sh ${video_id}
```
* **`video_id`** is the value of `v=` query param in `https://www.youtube.com/watch?v=${video_id}`

---

We use `youtube-dl` to download video information (`${video_id}.info.json`) and subtitles (`${video_id}.en.vtt`).

We read the info and replace placeholders in format `video_${placeholder}_prop` from the `pages/template.html` file.

We use `ffmpeg` to convert `vtt` into `srt` which is easier to parse. Each subtitle block starts with an index, next line is always time span and then the content. The text with timestamp is stored in a global variable as html `div`. When we're done reading all lines, we replace `video_transcript_prop` in the `template.html` file with the generated html.

We write the output to an html file `${video_id}.html` after minimizing it (~ 50% off) and gzip-ing it (~ 80% off).

### Pulling channel videos
```
$ ./gen_channel_vids_pages.sh ${channel_id} \
    [--since ${yyyy-mm-dd}] \
    [--max-concurrent 4]
```
* **`channel_id`** is id of youtube channel as found in `youtube.com/channel/${channel_od}` (NOT the channel name in `youtube.com/c/${channel_name}`)
* **`--since`** flag is to filter youtube videos which are older than provided date
* **`--max-concurrency`** flag is for how many videos to download at once (default 4)

---

We pull all videos from channel and generate pages for them. This functionality is used when we add new channel (without `--since` flag) and when we scrape new videos of existing channels periodically (with `--since` flag).

## Test videos
There are no tests for the logic so far. If we wanted to make tests, here is a list of videos to use:
* `MBnnXbOM5S4` control example
* `wL7tSgUpy8w` has autogen subtitles but there's only instrumental music
* `3x1b_S6Qp2Q` for benchmarking large videos, autogen subs
* `pTn6Ewhb27k` breaks the "timestamp, text, new line, next" pattern of autogen subtitles
* `ZxYOEwM6Wbk` youtube-dl exports duplicated subtitles

<!-- Invisible list of references -->
[aws-cli-install]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
[sitemap]: https://www.sitemaps.org/protocol.html
[aws-cli-dynamodb]: https://docs.aws.amazon.com/cli/latest/reference/dynamodb
