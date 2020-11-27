FROM debian:stretch

ENV BIN_DIRECTORY /usr/bin/subscanner
RUN mkdir -p "${BIN_DIRECTORY}"
WORKDIR "${BIN_DIRECTORY}"

# copies scripts and grants them exec permissions
COPY add_channel.sh .
COPY gen_channel_vids_pages.sh .
COPY gen_vid_page.sh .
COPY retry_failed_downloads.sh .
COPY upload_pages_to_s3.sh .
COPY lib.sh .
RUN chmod +x add_channel.sh \
    gen_channel_vids_pages.sh gen_vid_page.sh \
    retry_failed_downloads.sh upload_pages_to_s3.sh \
    lib.sh

# creates dir structure the scripts expect and copies over template files
RUN mkdir tmp pages sitemaps
COPY sitemaps/template.xml sitemaps/template.xml
COPY pages/template.html pages/template.html

RUN apt-get update -y
# necessary deps for the scripts
RUN apt-get install -y jq gzip ffmpeg
# necessary deps to for buildilng this image
RUN apt-get install -y wget tar curl unzip

# downloads minify dep, which scripts unnecessary bytes from html
# https://github.com/tdewolff/minify/releases
RUN mkdir minify_release
RUN wget https://github.com/tdewolff/minify/releases/download/v2.9.10/minify_linux_amd64.tar.gz
RUN tar -xvzf minify_linux_amd64.tar.gz -C minify_release
RUN mv minify_release/minify /usr/bin/minify
RUN chmod a+rx /usr/bin/minify
RUN rm -rf minify_release minify_linux_amd64.tar.gz

# downloads youtube-dl
RUN apt-get install -y python3-pip
RUN pip3 install --upgrade youtube-dl
RUN ln -s /usr/bin/python3 /usr/local/bin/python
# https://github.com/ytdl-org/youtube-dl/issues/14807
RUN apt-get install -y locales
RUN locale-gen en_US.UTF-8 && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# we need AWS CLI to upload the generated pages
# https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install
RUN rm awscliv2.zip
# https://github.com/aws/aws-cli/issues/5038
RUN apt-get install -y less

# doesn't do anything yet
CMD while true; do sleep 1; done
