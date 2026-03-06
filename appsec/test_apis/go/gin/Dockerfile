FROM golang:1.26-bookworm AS builder
WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=1 go build -o /out/appsec-test-api-go ./cmd/server

FROM gcr.io/distroless/base-debian12
WORKDIR /app

COPY --from=builder /out/appsec-test-api-go /app/appsec-test-api-go

EXPOSE 8000

CMD ["/app/appsec-test-api-go"]
