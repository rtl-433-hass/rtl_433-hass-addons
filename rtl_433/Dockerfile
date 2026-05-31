ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.23
# hadolint ignore=DL3006
FROM $BUILD_FROM AS builder

ENV LANG=C.UTF-8

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

ENV LANG=C.UTF-8

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

# Default rtl_433 configuration baked into the image
COPY rtl_433.defaults.conf /etc/rtl_433/rtl_433.defaults.conf

# Generate the TPMS protocol disables from THIS image's rtl_433 into a separate
# file. Every decoder whose '-R help' line mentions "TPMS" is disabled, so the
# disabled set always matches the rtl_433 version built above (protocol numbers
# shift between releases). The file is kept separate from the default config so
# run.sh can append it conditionally based on the 'disable_tpms' add-on option;
# when the option is off the disables are simply never appended. 'test -s' fails
# the build if nothing is generated (e.g. the help format changed), so the file
# is never silently empty.
# DL4006 (pipefail) is not used on purpose: 'rtl_433 -R help' may exit non-zero,
# and the 'test -s' check is what actually guards the result.
# hadolint ignore=DL4006
RUN { echo "# TPMS protocol disables generated at image build time from"; \
      echo "# 'rtl_433 -R help'. Appended per-radio by run.sh when the"; \
      echo "# 'disable_tpms' add-on option is enabled. Not user-editable."; \
    } > /etc/rtl_433/rtl_433.tpms-disables.conf \
    && rtl_433 -R help 2>&1 \
      | sed -nE 's/^[[:space:]]*\[[[:space:]]*([0-9]+)\][*]?[[:space:]]+.*[Tt][Pp][Mm][Ss].*/protocol -\1/p' \
      >> /etc/rtl_433/rtl_433.tpms-disables.conf \
    && grep -q '^protocol -' /etc/rtl_433/rtl_433.tpms-disables.conf

# Run script
COPY run.sh /
# hadolint ignore=DL3059
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
