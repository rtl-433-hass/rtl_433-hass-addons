ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21
# hadolint ignore=DL3006
FROM $BUILD_FROM AS builder

ENV LANG C.UTF-8

# Copied with minor edits from https://github.com/hertzg/rtl_433_docker/blob/master/images/alpine/build-context/Dockerfile
# DL3018 (pin apk versions) is ignored on purpose: Alpine removes superseded
# package versions from its repos, so exact pins break the build as soon as a
# patch ships upstream.
# hadolint ignore=DL3018
RUN apk add --no-cache --virtual .buildDeps \
    build-base \
    libusb-dev \
    hackrf \
    hackrf-dev \
    librtlsdr-dev \
    soapy-sdr \
    soapy-sdr-dev \
    openssl-dev \
    cmake \
    git

WORKDIR /build

FROM builder AS rtl_433_builder

RUN git clone https://github.com/merbanan/rtl_433
WORKDIR /build/rtl_433

# Build a specific commit or tag.
ARG rtl433GitRevision=25.12
# hadolint ignore=DL3059
RUN git checkout ${rtl433GitRevision}
WORKDIR /build/rtl_433/build
# hadolint ignore=DL3059
RUN cmake ..
# hadolint ignore=DL3059
RUN make -j 4

WORKDIR /build/root
WORKDIR /build/rtl_433/build
RUN make DESTDIR=/build/root/ install

FROM builder AS soapy_hackrf_builder
RUN git clone https://github.com/pothosware/SoapyHackRF.git
WORKDIR /build/SoapyHackRF
# hadolint ignore=DL3059
RUN git checkout 6c0c33f0aa44c3080674e6bca0273184d3e9eb44
WORKDIR /build/SoapyHackRF/build
# hadolint ignore=DL3059
RUN cmake ..
# hadolint ignore=DL3059
RUN make -j4
# hadolint ignore=DL3059
RUN make install

# hadolint ignore=DL3006
FROM $BUILD_FROM

ENV LANG C.UTF-8

# DL3018 (pin apk versions) is ignored on purpose: Alpine removes superseded
# package versions from its repos, so exact pins break the build as soon as a
# patch ships upstream.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    libusb \
    hackrf \
    librtlsdr \
    soapy-sdr \
    sed
WORKDIR /root
COPY --from=rtl_433_builder /build/root/ /

COPY --from=soapy_hackrf_builder /usr/lib /lib-s
# hadolint ignore=DL3059
RUN mkdir -p /usr/local/lib/SoapySDR/modules0.8/
COPY --from=soapy_hackrf_builder /usr/local/lib/SoapySDR/modules0.8/libHackRFSupport.so /usr/local/lib/SoapySDR/modules0.8/

# Run script
COPY run.sh /
# hadolint ignore=DL3059
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
