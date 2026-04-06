FROM golang:1.26-bookworm AS builder
WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=1 go build -o /out/server ./cmd/server

FROM gcr.io/distroless/base-debian12
WORKDIR /app

COPY --from=builder /out/server /app/server

EXPOSE 8000

CMD ["/app/server"]
