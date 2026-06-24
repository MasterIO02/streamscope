# Build stage
FROM haxe:4.3-alpine AS build

RUN apk add --no-cache g++ make

# musl doesn't ship xlocale.h, hxcpp expects it
RUN ln -s /usr/include/locale.h /usr/include/xlocale.h

RUN haxelib setup /root/haxelib && \
    haxelib install hxcpp 4.3.2 && \
    haxelib install hxWebSockets 1.4.0

WORKDIR /src
COPY . .

RUN haxe compile.hxml

# Runtime stage
# we have to use a base python image to install streamlink via pip
FROM python:3-alpine

RUN apk add --no-cache ffmpeg ca-certificates && \
    pip install --no-cache-dir streamlink

COPY --from=build /src/appbuild/streamscope /usr/local/bin/

WORKDIR /home/streamscope

ENTRYPOINT ["/usr/local/bin/streamscope", "./list.txt"]
