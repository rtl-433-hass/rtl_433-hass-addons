ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21
# hadolint ignore=DL3006
FROM $BUILD_FROM as builder

ENV LANG C.UTF-8

# Copied with minor edits from https://github.com/hertzg/rtl_433_docker/blob/master/images/alpine/build-context/Dockerfile
RUN apk add --no-cache --virtual .buildDeps \
    build-base=0.5-r3 \
    libusb-dev=1.0.27-r0 \
    hackrf=2024.02.1-r0 \
    hackrf-dev=2024.02.1-r0 \
    librtlsdr-dev=2.0.2-r0 \
    soapy-sdr=0.8.1-r3 \
    soapy-sdr-dev=0.8.1-r3 \
    openssl-dev=3.3.5-r0 \
    cmake=3.31.1-r0 \
    git=2.47.3-r0

WORKDIR /build

FROM builder as rtl_433_builder

RUN git clone https://github.com/merbanan/rtl_433
WORKDIR /build/rtl_433

# Build a specific commit or tag.
ARG rtl433GitRevision=25.12
RUN git checkout ${rtl433GitRevision}
WORKDIR /build/rtl_433/build
RUN cmake ..
RUN make -j 4

WORKDIR /build/root
WORKDIR /build/rtl_433/build
RUN make DESTDIR=/build/root/ install

FROM builder as soapy_hackrf_builder
RUN git clone https://github.com/pothosware/SoapyHackRF.git
WORKDIR /build/SoapyHackRF
RUN git checkout 6c0c33f0aa44c3080674e6bca0273184d3e9eb44
WORKDIR /build/SoapyHackRF/build
RUN cmake ..
RUN make -j4
RUN make install

# hadolint ignore=DL3006
FROM $BUILD_FROM

ENV LANG C.UTF-8

RUN apk add --no-cache \
    libusb=1.0.27-r0 \
    hackrf=2024.02.1-r0 \
    librtlsdr=2.0.2-r0 \
    soapy-sdr=0.8.1-r3 \
    sed=4.9-r2
WORKDIR /root
COPY --from=rtl_433_builder /build/root/ /

COPY --from=soapy_hackrf_builder /usr/lib /lib-s
RUN mkdir -p /usr/local/lib/SoapySDR/modules0.8/
COPY --from=soapy_hackrf_builder /usr/local/lib/SoapySDR/modules0.8/libHackRFSupport.so /usr/local/lib/SoapySDR/modules0.8/

# Run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
