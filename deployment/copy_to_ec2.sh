#!/bin/bash

## Given instance name and sitemap file, copies deployment files to it.
## A EBS docker deployment file would be better, but too much setting up for now.

readonly instance_name=$1
readonly sitemap=$2

if [ -z "${instance_name}" ]; then
    echo "Instance name must be provided as first arg."
    exit 1
fi

if [ -z "${sitemap}" ]; then
    echo "Sitemap must be provided as second arg."
    exit 1
fi

readonly INSTANCE_USER="ec2-user"

function run_ssh_cmd() {
    ## Executes given bash command over ssh.

    local cmd=$1

    echo $(ssh -t -i "${PEM_PATH}" "${INSTANCE_USER}@${instance_name}" "${cmd}")
}

run_ssh_cmd "mkdir env"

# copy run script which pulls image and starts container
rsync -e "ssh -i ${PEM_PATH}" \
    start_sqs_poll.sh \
    "${INSTANCE_USER}@${INSTANCE_NAME}":"/home/${INSTANCE_USER}/start_sqs_poll.sh"
# you need to create the env dir first at the target instance, then you can sync
# the local .env file
rsync -e "ssh -i ${PEM_PATH}" \
    ../.env \
    "${INSTANCE_USER}@${INSTANCE_NAME}":"/home/${INSTANCE_USER}/env/.env"

run_ssh_cmd "SITEMAP=${SITEMAP} ./start_sqs_poll.sh"
