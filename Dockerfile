ARG IMAGE="alpine:3.20.3"

FROM ${IMAGE} AS builder

RUN apk update && apk upgrade && apk add zig

WORKDIR /app

COPY src src
COPY build.zig build.zig.zon ./

RUN zig build --release=safe

FROM ${IMAGE}
WORKDIR /app

COPY --from=builder /app/zig-out ./

ENTRYPOINT ["/app/bin/protohackers_zig"]
