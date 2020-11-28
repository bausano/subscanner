#!/bin/bash

## Given instance name and sitemap file, copies deployment files to it.

# TODO(https://github.com/bausano/subscanner/issues/20): A EBS docker deployment
# file would be better.

# TODO: Ideally configure a monitor process which shuts down the EC2 instance.
# The instance can be configured to terminate after shut down. And the container
# exists when 429 is returned. Hence 429 -> cont dies -> shut down -> terminate.
# Also it'd be nice to have a script which can spawn ec2.

set -e

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

if [ ! -f "${PEM_PATH}" ]; then
    echo "PEM_PATH must be provided."
    exit 1
fi

readonly INSTANCE_USER="ec2-user"

function run_ssh_cmd() {
    ## Executes given bash command over ssh.

    local cmd=$1

    echo $(ssh -t -i "${PEM_PATH}" "${INSTANCE_USER}@${instance_name}" "${cmd}")
}

# # install docker
run_ssh_cmd "sudo yum install -y docker"
run_ssh_cmd "sudo usermod -aG docker ec2-user"
run_ssh_cmd "sudo service docker start"

# copy run script which pulls image and starts container
rsync -e "ssh -i ${PEM_PATH}" \
    deployment/start_sqs_poll.sh \
    "${INSTANCE_USER}@${instance_name}":"/home/${INSTANCE_USER}/start_sqs_poll.sh"

# copy over env
run_ssh_cmd "mkdir env"
rsync -e "ssh -i ${PEM_PATH}" \
    .env \
    "${INSTANCE_USER}@${instance_name}":"/home/${INSTANCE_USER}/env/.env"

run_ssh_cmd "./start_sqs_poll.sh ${sitemap}"
