FROM node:18-alpine3.19 as builder

RUN echo '@edgemain http://dl-4.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories &&\
    echo '@edgecommunity http://dl-4.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories &&\
    apk add --no-cache zlib tiff libjpeg-turbo fcgi libmemcached libpng lcms2 \
      libimagequant@edgemain fftw@edgemain vips vips-tools
RUN apk add --no-cache bash build-base git autoconf automake libtool cmake pkgconfig\
      zlib-dev tiff-dev libpng-dev libjpeg-turbo-dev pkgconf-dev fcgi-dev libmemcached-dev lcms2-dev\
      python3 vips-dev fftw-dev@edgemain libimagequant-dev@edgemain &&\
    cd /root &&\
    git clone --verbose https://github.com/uclouvain/openjpeg.git &&\
    git clone --verbose https://github.com/ruven/iipsrv.git
ARG C_FLAGS=" -O3 -DNDEBUG"
ENV CFLAGS ${C_FLAGS}
ENV CXXFLAGS ${C_FLAGS}
RUN cd /root/openjpeg &&\
    echo cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_C_FLAGS="\"$CFLAGS\"" . &&\
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_C_FLAGS="$CFLAGS" . &&\
    echo "export openjpeg_version=$(git describe --tags --always)" > /root/versions &&\
    make -j 8
RUN cd /root/iipsrv &&\
    bash ./autogen.sh &&\
    echo CFLAGS=$CFLAGS CXXFLAGS=$CXXFLAGS &&\
    bash ./configure --enable-openjpeg --with-openjpeg=/root/openjpeg &&\
    echo "export iipsrv_version=$(git describe --tags --always)" >> /root/versions &&\
    make -j 8
# RUN npm -g install sharp --build-from-source --unsafe &&\
#     cd /usr/local/lib/node_modules &&\
#     tar -cjf sharp.tar.bz2 sharp

FROM alpine:3.19

RUN echo '@edgemain http://dl-4.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories &&\
    echo '@edgecommunity http://dl-4.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories &&\
    apk add --no-cache fcgi zlib tiff libjpeg-turbo fcgi libmemcached libpng libgomp lcms2 \
      libimagequant@edgemain fftw@edgemain vips vips-tools &&\
    apk add lighttpd && apk del lighttpd &&\
    rm -rf /var/cache/apk/* &&\
    adduser -S -u 9000 -G www-data iipsrv
COPY --from=builder /root/openjpeg/bin/*.so* /root/openjpeg/bin/*.a* /usr/lib/
COPY --from=builder /root/openjpeg/bin/opj_* /usr/bin/
WORKDIR /
COPY --from=builder /root/iipsrv/src/iipsrv.fcgi /root/versions /
EXPOSE 9000
# user iipsrv, kubernetes checks non-root with numbers
USER 9000
ENV FILESYSTEM_PREFIX=/mnt/data/forIIIF/ IIIF_VERSION=2

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD [ "/usr/bin/cgi-fcgi", "-bind", "-connect", "localhost:9000" ]

ENTRYPOINT ["/iipsrv.fcgi", "--bind", "0.0.0.0:9000"]