ARG SYNAPSE_VERSION=latest
ARG HARDENED_MALLOC_VERSION=11
ARG UID=991
ARG GID=991


### Build Hardened Malloc
FROM alpine:latest as build-malloc

ARG HARDENED_MALLOC_VERSION
ARG CONFIG_NATIVE=false
ARG VARIANT=default

RUN apk -U upgrade \
 && apk --no-cache add build-base git gnupg && cd /tmp \
 && wget -q https://github.com/thestinger.gpg && gpg --import thestinger.gpg \
 && git clone --depth 1 --branch ${HARDENED_MALLOC_VERSION} https://github.com/GrapheneOS/hardened_malloc \
 && cd hardened_malloc && git verify-tag $(git describe --tags) \
 && make CONFIG_NATIVE=${CONFIG_NATIVE} VARIANT=${VARIANT}


### Build Synapse
FROM python:alpine as builder

ARG SYNAPSE_VERSION

RUN apk -U upgrade \
 && apk add --no-cache -t build-deps \
        build-base \
        libffi-dev \
        libjpeg-turbo-dev \
        libressl-dev \
        libxslt-dev \
        linux-headers \
        postgresql-dev \
        rustup \
        zlib-dev \
        git \
 && rustup-init -y && source $HOME/.cargo/env \
 && pip install --upgrade pip \
 && pip install --prefix="/install" --no-warn-script-location \
   -e "git+https://mau.dev/maunium/synapse#egg=matrix-synapse[all]==${SYNAPSE_VERSION}"

### Build Production

FROM python:alpine

ARG UID
ARG GID

RUN apk -U upgrade \
 && apk add --no-cache -t run-deps \
        libffi \
        libgcc \
        libjpeg-turbo \
        libressl \
        libstdc++ \
        libxslt \
        libpq \
        zlib \
        tzdata \
        xmlsec \
        git \
        curl \
        icu-libs \
 && adduser -g ${GID} -u ${UID} --disabled-password --gecos "" synapse \
 && rm -rf /var/cache/apk/*

RUN pip install --upgrade pip \
 && pip install -e "git+https://github.com/matrix-org/mjolnir.git#egg=mjolnir&subdirectory=synapse_antispam"

COPY --from=build-malloc /tmp/hardened_malloc/out/libhardened_malloc.so /usr/local/lib/
COPY --from=builder /install /usr/local
COPY --chown=synapse:synapse rootfs /

ENV LD_PRELOAD="/usr/local/lib/libhardened_malloc.so"

USER synapse

VOLUME /data

EXPOSE 8008/tcp 8009/tcp 8448/tcp

ENTRYPOINT ["python3", "start.py"]

HEALTHCHECK --start-period=5s --interval=15s --timeout=5s \
    CMD curl -fSs http://localhost:8008/health || exit 1