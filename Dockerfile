FROM curlimages/curl:7.84.0 AS builder
ARG FIRMWARE_VERSION=0.17.781

WORKDIR /tmp/obs
RUN curl --remote-name --location https://github.com/openbikesensor/OpenBikeSensorFirmware/releases/download/v${FIRMWARE_VERSION}/obs-v${FIRMWARE_VERSION}-initial-flash.zip && \
    curl --remote-name --location  https://github.com/openbikesensor/OpenBikeSensorFlash/releases/latest/download/flash.bin && \
	unzip obs-v${FIRMWARE_VERSION}-initial-flash.zip && \
	rm obs-v${FIRMWARE_VERSION}-initial-flash.zip

COPY --chown=100 ./public-html/ ./
RUN sed -i "s/FIRMWARE_VERSION/${FIRMWARE_VERSION}/g" /tmp/obs/index.html && \
    sed -i "s/FIRMWARE_VERSION/${FIRMWARE_VERSION}/g" /tmp/obs/manifest.json && \
    mv /tmp/obs/manifest.json /tmp/obs/manifest-${FIRMWARE_VERSION}.json

RUN for file in *.bin; \
    do \
        if [ -f "$file" ]; \
        then \
            sha256=`sha256sum -b ${file} | cut -c1-32`; \
            mv ${file} ${sha256}-${file}; \
            sed -i "s/${file}/${sha256}-${file}/g" manifest-*.json; \
        fi \
    done

RUN chmod -R a=rX .

FROM node:16-bullseye AS nodebuilder
ARG ESP_WEB_TOOLS_VERSION=9.0.3

WORKDIR /tmp/esp-web-tool
RUN curl --remote-name --location https://github.com/esphome/esp-web-tools/archive/refs/tags/${ESP_WEB_TOOLS_VERSION}.zip && \
    unzip *.zip && \
    rm *.zip && \
    mv */* . && \
# until https://github.com/esphome/esp-web-tools/issues/270 is fixed
    sed -i 's|esptool-js/esploader.js|esptool-js/ESPLoader.js|g' src/flash.ts && \
# increase speed
    sed -i 's|esploader.flash_id();|esploader.flash_id();\n    await esploader.change_baud();|g' src/flash.ts && \
    sed -i 's|115200|921600|g' src/flash.ts && \
    npm ci  && \
    script/build && \
    npm exec -- prettier --check src && \
    chmod -R a=rX /tmp/esp-web-tool/dist


FROM httpd:2.4

COPY --chown=nobody:nogroup --from=builder /tmp/obs/ /usr/local/apache2/htdocs/
COPY --chown=nobody:nogroup --from=nodebuilder /tmp/esp-web-tool/dist/web/ /usr/local/apache2/htdocs/esp-web-tools

