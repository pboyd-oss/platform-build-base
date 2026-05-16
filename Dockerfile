FROM harbor.tuxgrid.com/platform/base:latest

ARG HTTPS_PROXY
ARG HTTP_PROXY

RUN printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$HTTP_PROXY" "$HTTPS_PROXY" \
      > /etc/apt/apt.conf.d/99proxy \
    && apt-get update && apt-get install -y --no-install-recommends \
    make \
    gcc \
    build-essential \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/* /etc/apt/apt.conf.d/99proxy

CMD ["cat"]
