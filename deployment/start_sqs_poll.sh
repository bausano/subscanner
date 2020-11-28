#!/bin/bash

## Pulls subscanner docker image and runs it.

# IMPORTANT! change if using multiple machines (sitemapN.xml)
sitemap=${SITEMAP:-"sitemap1.xml"}

image_name="porkbrain/subscanner:latest"
cont_name="subscanner"

echo "Pulling image ${image_name}..."
docker pull "${image_name}"

echo "Running image ${image_name}..."
docker run --detach \
    -v "${PWD}/env":/subscanner/env \
    -e ENV_FILE_PATH=/subscanner/env/.env \
    -e SITEMAP="${sitemap}" \
    --name "${cont_name}" \
    "${image_name}"
