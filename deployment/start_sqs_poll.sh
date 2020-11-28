#!/bin/bash

## Pulls subscanner docker image and runs it.

readonly host_env_dir="${PWD}/env"
if [ ! -f "${host_env_dir}/.env" ]; then
    echo "No env file found at '${host_env_dir}/.env'."
    exit 1
else
    source "${host_env_dir}/.env"
fi

if [ -z "${SITEMAP}" ]; then
    echo "SITEMAP env var must be provided."
    exit 1
fi

readonly IMG_NAME="porkbrain/subscanner:latest"
readonly CONT_NAME="subscanner"

echo "Pulling image ${IMG_NAME}..."
docker pull "${IMG_NAME}"

echo "Running image ${IMG_NAME}..."
docker run --detach \
    -v "${host_env_dir}":/subscanner/env \
    -e ENV_FILE_PATH=/subscanner/env/.env \
    -e SITEMAP="${SITEMAP}" \
    --name "${CONT_NAME}" \
    "${IMG_NAME}"
