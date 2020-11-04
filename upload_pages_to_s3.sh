#!/bin/bash

# Uploads all files in the `pages` directory to an S3 bucket using AWS CLI v2.
# You will need to set up AWS credentials with access to the bucket. See
# the README for more instructions.

if ! command -v aws &> /dev/null
then
    echo "AWS CLI is missing. Follow the official guide at"
    echo "https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
    exit 1
fi

readonly DIR_TO_SYNC="pages"

readonly bucket=$1
if [ -z "${bucket}" ]; then
    echo "Bucket name must be provided. Example: ./upload_pages_to_s3 my-bucket"
    exit 1
fi

# Exports the .env file environment variables if present.
if test -f ".env"; then
    echo "(source .env)"
    source .env
fi

aws s3 sync "${DIR_TO_SYNC}" "s3://${bucket}" \
    --acl "public-read" `# everyone can access since it's website` \
    --storage-class "REDUCED_REDUNDANCY" `# cheaper storage` \
    --exclude "*" --include "*.html" `# only html files` \
    --content-type "text/html" \
    --content-encoding "gzip" `# pages are gzipped in 'gen_html_for_vid.sh' step` \
    --cache-control "public, max-age=604800, immutable" `# content never changes`

echo "[$(date)] Done!"
