#!/bin/bash

source lib.sh

readonly help='
Uploads all files in the `pages` directory to an S3 bucket using AWS CLI v2.
You will need to set up AWS credentials with access to the bucket. See
the README for more instructions.
* bucket name id
* flag `--sitemap` with the name of the sitemap file stored in S3 to append new
    videos to (if the file does not exist we create new one)
* flag `--domain` with the domain name, used for sitemap links

$ ./upload_pages_to_s3.sh ${bucket_name} --sitemap "sitemap1.xml"
'
if [ "${1}" = "help" ]; then echo "${help}" && exit 0; fi

check_dependency "aws"

readonly PAGES_DIR_TO_SYNC="pages"

readonly bucket_name=$1
if [ -z "${bucket_name}" ]; then
    echo "Bucket name must be provided. See ./upload_pages_to_s3 help"
    exit 1
fi

for key in "$@"; do
    case ${key} in
        --sitemap)
        readonly sitemap_file=$2
        ;;
        --domain)
        readonly domain=$2
        ;;
    esac
    # go to next flag
    shift
done

if [ -z "${sitemap_file}" ]; then
    echo "Sitemap file must be provided. See ./upload_pages_to_s3 help"
    exit 1
fi

if [ -z "${domain}" ]; then
    echo "Domain must be provided. See ./upload_pages_to_s3 help"
    exit 1
fi

# Imports the .env file environment variables if present.
if test -f ".env"; then
    echo "(source .env)"
    source .env
fi

# reads all gen pages, return only file names (no /pages path)
readonly pages=$(find pages/*.html -not -path pages/template.html -printf "%f\n")
if [[ ${#pages} -eq 0 ]]; then
    echo "No pages to upload."
    exit 1
fi

# copies sitemap file if exists, returns 1 if not
aws s3 cp "s3://${bucket_name}/${sitemap_file}" "sitemaps"

# https://stackoverflow.com/q/4881930/5093093
# if exists read all but last line, which means closing </urlset> is dropped
if [[ $? == 0 ]]; then
    echo "[$(date)] Downloaded sitemap"
    sitemap_content_mut=$(head -n -1 "sitemaps/${sitemap_file}")
else
    echo "[$(date)] Creating new sitemap"
    sitemap_content_mut=$(head -n -1 "sitemaps/template.xml")
fi

while read html_file_name;
do
    sitemap_content_mut+="<url><loc>https://${domain}/${html_file_name}</loc></url>"
done <<< "${pages}"

# closes the sitemap as we read `head -n -1`
sitemap_content_mut+=$'\n</urlset>'

# stores the file and copies it to S3
echo "[$(date)] Uploading sitemap..."
echo "${sitemap_content_mut}" > "sitemaps/${sitemap_file}"
aws s3 cp \
    "sitemaps/${sitemap_file}" \
    "s3://${bucket_name}/${sitemap_file}" \
    --acl "public-read"
abort_on_err $? "Cannot copy sitemap"

echo "[$(date)] Uploading all pages..."
aws s3 sync "${PAGES_DIR_TO_SYNC}" "s3://${bucket_name}" \
    --acl "public-read" `# everyone can access since it's website` \
    --storage-class "REDUCED_REDUNDANCY" `# cheaper storage` \
    --exclude "*" --include "*.html" `# only html files` \
    --exclude "template.html" \
    --content-type "text/html" \
    --content-encoding "gzip" `# pages are gzipped in 'gen_vid_page.sh' step` \
    --cache-control "public, max-age=604800, immutable" `# content never changes`

echo "[$(date)] Removing local page copies..."
(
    cd pages
    rm ${pages}
)

echo "[$(date)] Done!"
