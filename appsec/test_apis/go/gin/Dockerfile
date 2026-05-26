FROM golang:1.25-bookworm AS builder
WORKDIR /src

RUN go install github.com/DataDog/orchestrion@latest

COPY . .
RUN orchestrion pin

RUN CGO_ENABLED=1 orchestrion go build -o /out/appsec-test-api-go ./cmd/server

FROM debian:bookworm-slim
WORKDIR /app

COPY --from=builder /out/appsec-test-api-go /app/appsec-test-api-go

EXPOSE 8000

CMD ["/app/appsec-test-api-go"]
