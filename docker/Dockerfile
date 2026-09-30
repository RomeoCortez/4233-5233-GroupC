# Version family deliberately selected; lock a reviewed patch/digest before production.
ARG NEXTCLOUD_BASE=nextcloud:32-apache
FROM ${NEXTCLOUD_BASE}
COPY docker/custom.config.php /usr/src/nextcloud/config/custom.config.php
