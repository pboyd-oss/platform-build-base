FROM harbor.tuxgrid.com/platform/base:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    gcc \
    build-essential \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

CMD ["cat"]
