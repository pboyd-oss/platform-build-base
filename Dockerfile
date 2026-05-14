FROM harbor.tuxgrid.com/platform/base:latest

ARG HTTPS_PROXY
ARG HTTP_PROXY

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    gcc \
    build-essential \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

CMD ["cat"]
