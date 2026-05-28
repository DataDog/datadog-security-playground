FROM golang:1.25-bookworm AS builder
WORKDIR /src

RUN go install github.com/DataDog/orchestrion@latest

COPY . .
RUN orchestrion pin

RUN CGO_ENABLED=1 orchestrion go build -o /out/appsec-test-api-go ./cmd/server

FROM debian:bookworm-slim

# GIT_SHA pins payload downloads from Github to the commit the image was built
# from so scenarios stay reproducible. Defaults to "main" for bare
# `docker build`; CI passes the real SHA.
ARG GIT_SHA=main
ENV GIT_SHA=${GIT_SHA}

# curl:     download payloads in the shi-rce-malware scenario
# dnsutils: dig to mining pools in the rce-malware payload
# procps:   pkill for cleanup in the rce-malware payload
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl dnsutils procps \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /out/appsec-test-api-go /app/appsec-test-api-go

EXPOSE 8000

CMD ["/app/appsec-test-api-go"]
