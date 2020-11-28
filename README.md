# subscanner

[![Docker build][docker-image-badge]][docker-image]

At the moment of writing the app, there is no way to search YouTube video content as its not indexed by browsers. The solution to this problem is an app which scrapes YouTube subtitles APIs and creates an html file with the transcript. The html files are uploaded to an S3 bucket. The content is indexed by search engines.

We only scrape subs written by humans as auto generated subtitles are of poor quality.

## Dependencies
You must have [`youtube-dl`](youtube-dl) utility installed to fetch the subs and `jq` to query info json file. Then `minify` for html size reduction and `gzip` to serve gzip file to clients. We use `ffmpeg` to convert from `vtt` to `srt` which is much easier to parse.

```bash
$ apt-get install -y jq minify gzip ffmpeg
```

See the [`Dockerfile`](Dockerfile) for source from which you can download `youtube-dl`.

You must [install AWS CLI][aws-cli-install] and [configure your environment](#publishing-to-web).

```bash
$ aws --version
aws-cli/2.0.61
```

You might need to grant executable permission to the bash scripts.

```bash
$ chmod +x add_channel.sh \
    gen_channel_vids_pages.sh gen_vid_page.sh \
    retry_failed_downloads.sh upload_pages_to_s3.sh
```

## How it works
Each script accepts `help` as first argument, in which case it will print its documentation and exit.

You need to `cd src` before you start running the scripts for the moment due to relative paths used for another scripts and directories.

### Persistence
```bash
$ ./add_channel.sh ${channel_id} [--max-concurrent 4]
```
* **`channel_id`** is id of youtube channel as found in `youtube.com/channel/${channel_od}` (NOT the channel name in `youtube.com/c/${channel_name}`)
* **`DB_NAME`** env var is for name of AWS DynamoDB table which stores timestamp of channel last scape
* **`--max-concurrent`** flag is for how many videos to download at once (default 1)

---

In [DynamoDB table][aws-cli-dynamodb] we store `channel_id` as string primary key and each row has associated `updated_at` number value (unix timestamp). Every time we revisit channel to scrape new videos, we update the `updated_at` value in db.

The `add_channel.sh` script is used to add new entries to db. It will scrape all videos to date and store them in `pages` directory.

Should we want to access list of all videos we've scraped, we can list the objects in the S3 bucket. However this level of granularity is not necessary.

### Publishing to web
```bash
$ ./upload_pages_to_s3.sh --sitemap ${sitemap_file_name_on_s3}
```
* **`BUCKET_NAME`** env var is name of AWS S3 bucket to upload the generated html files located in `pages` dir to
* **`DOMAIN_NAME`** env var is for the name of the domain to create URLs for in sitemap
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
```bash
$ ./gen_vid_page.sh ${video_id}
```
* **`video_id`** is the value of `v=` query param in `https://www.youtube.com/watch?v=${video_id}`

---

We use `youtube-dl` to download video information (`${video_id}.info.json`) and subtitles (`${video_id}.en.vtt` or any other IETF lang tag instead of `en`).

We read the info and replace placeholders in format `video_${placeholder}_prop` from the `pages/template.html` file.

We use `ffmpeg` to convert `vtt` into `srt` which is easier to parse. Each subtitle block starts with an index, next line is always time span and then the content. The text with timestamp is stored in a global variable as html `div`. When we're done reading all lines, we replace `video_transcript_prop` in the `template.html` file with the generated html.

We write the output to an html file `${video_id}.html` after minimizing it (~ 50% off) and gzip-ing it (~ 80% off).

### Pulling channel videos
```bash
$ ./gen_channel_vids_pages.sh ${channel_id} \
    [--since ${yyyy-mm-dd}] \
    [--max-concurrent 4]
```
* **`channel_id`** is id of youtube channel as found in `youtube.com/channel/${channel_od}` (NOT the channel name in `youtube.com/c/${channel_name}`)
* **`--since`** flag is to filter youtube videos which are older than provided date
* **`--max-concurrent`** flag is for how many videos to download at once (default 1)

---

We pull all videos from channel and generate pages for them. This functionality is used when we add new channel (without `--since` flag) and when we scrape new videos of existing channels periodically (with `--since` flag).

### Fault tolerance
```bash
$ ./retry_failed_downloads.sh [--max-concurrent 4]
```
* **`--max-concurrent`** flag is for how many videos to download at once (default 1)

---

The script above retries to fetch all videos which have failed so far. Often videos would fail because they don't have any subtitles, but that's not always the case.

Sometimes script fail in places I assumed it wouldn't. In bash the error handling story is extremely annoying.

### Default running mode
```bash
$ ./listen_to_sqs.sh --sitemap "sitemap1.xml" \
    [--max-concurrent 4] \
    [--upload-after 10] \
    [--retry-failed-after M]
```
* **`SQS_URL`** env var tells us which queue to poll
* **`--sitemap`** flag is for the name of the xml file in S3 which will be appended new page URLs (if the file doesn't exist, new is created from sitemap template)
* optional **`--upload-after N`** flag sets after how many downloaded channels should we push generated html to S3. Defaults to 10.
* optional **`--retry-failed-after M`** flag says how many channels to process
    before retrying all failed videos. If not provided, retry procedure is not
    ran.
* **`--max-concurrent`** flag is for how many videos to download at once (default 1)

---

Polls sqs messages with channel ids. For each message it reads, it starts the procedure for adding channel. Every _N_ messages it uploads all scraped pages to S3. Every _M_ messages it retries downloading failed videos.

Useful if you want to have a script which never exists and keeps listening to more work.

## Docker
Build docker image with `$ docker build --tag subscanner:1.0.0 .` (with correct version). You will need to either provide all env vars from `.env.example` file or provide `ENV_FILE_PATH` env var which points to a copy of the example.

It is important to provide sitemap file name which will be used for deployment. If you want to have several docker images running, you must provide different sitemap file name to each to avoid data races.

Default docker CMD launches the container into [default running mode](#default-running-mode).

```bash
docker run --detach \
    -e AWS_ACCESS_KEY_ID=XXX \
    -e AWS_SECRET_ACCESS_KEY=XXX \
    -e BUCKET_NAME=XXX \
    -e DOMAIN_NAME=XXX \
    -e DB_NAME=XXX \
    -e SITEMAP=sitemap1.xml
    --name subscanner subscanner:1.0.0
```

or

```bash
docker run --detach \
    -v "${PWD}/env":/subscanner/env \
    -e ENV_FILE_PATH=/subscanner/env/.env \
    -e SITEMAP=sitemap1.xml \
    -e MAX_CONCURRENT=2 \
    --name subscanner subscanner:1.0.0
```

If you're deploying this app to ec2 instance, following installs docker.

```bash
sudo yum update -y
sudo yum install -y docker
sudo usermod -aG docker ec2-user
sudo service docker start
mkdir env # we will use this to store env file
```

And now we copy `start_sqs_poll.sh` script and `.env` file to the instance.

```bash
PEM_PATH="/home/user/.ssh/key.pem"
INSTANCE_NAME="ec2-1-2-3-4.eu-west-1.compute.amazonaws.com"
# copy run script which pulls image and starts container
rsync -e "ssh -i ${PEM_PATH}" \
    deployment/start_sqs_poll.sh \
    "ec2-user@${INSTANCE_NAME}":/home/ec2-user/start_sqs_poll.sh
# you need to create the env dir first at the target instance, then you can sync
# the local .env file
rsync -e "ssh -i ${PEM_PATH}" \
    .env \
    "ec2-user@${INSTANCE_NAME}":/home/ec2-user/env/.env
```

Now you can ssh into the instance and run the script.

## Concurrency
Scripts accept `--max-concurrent N` flag or `MAX_CONCURRENT` env var which sets maximum number of videos we download subs for at one given moment. Value of ~4 will get your IP banned by Youtube servers if overused (~1000 videos a day).

Another gotcha caused by using S3 are sitemap data races. If you have processes uploading pages to S3 at once, make sure they all work with different sitemap files! Use `--sitemap FILE NAME` flag to control which sitemap is being updated.

## Cheatsheet and useful links
```bash
# print line by line video released date and id in format of YYYYMMDD.video_id
youtube-dl --simulate --get-filename -o '%(upload_date)s.%(id)s' ${channel_id}
```

Use [socialnewsify.com/get-channel-id-by-username-youtube]([channel-name-to-id]) tool to get channel id from username.

To avoid getting error 429, one can try to follow:

> Here the steps I followed:
    \
    * if you use Firefox, install addon cookies.txt, enable the addon
    \
    * clear your browser cache, clear you browser cookies (privacy reasons)
    \
    * go to google.com, and log in with your google account
    \
    * go to youtube.com
    \
    * click on the cookies.txt addon, and export the cookies, save it as cookies.txt (in the same directory from where you are going to run youtube-dl)
    \
    * this worked for me ... youtube-dl --cookies cookies.txt https://www.youtube.com/watch?v=....
    \
    \
    https://www.reddit.com/r/youtubedl/comments/ejgy2l/yt_banning_ips_with_http_error_429_too_many/fsymxh7


<!-- References -->
[youtube-dl]: https://github.com/ytdl-org/youtube-dl
[aws-cli-install]: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
[sitemap]: https://www.sitemaps.org/protocol.html
[aws-cli-dynamodb]: https://docs.aws.amazon.com/cli/latest/reference/dynamodb
[docker-image]: https://hub.docker.com/repository/docker/porkbrain/subscanner/general
[docker-image-badge]: https://img.shields.io/docker/cloud/build/porkbrain/subscanner.svg
[channel-name-to-id]: https://socialnewsify.com/get-channel-id-by-username-youtube/
