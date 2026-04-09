FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN go build -o simulator ./cmd/server && \
    go build -o bin/scenarios/auth-brute-force  ./scenarios/01-auth-brute-force && \
    go build -o bin/scenarios/payment-decline   ./scenarios/02-payment-decline && \
    go build -o bin/scenarios/db-slow-query     ./scenarios/03-db-slow-query && \
    go build -o bin/scenarios/cache-stampede    ./scenarios/04-cache-stampede && \
    go build -o bin/scenarios/api-degradation   ./scenarios/05-api-degradation

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/simulator .
COPY --from=builder /app/bin ./bin
RUN mkdir -p /app/logs
EXPOSE 8080
CMD ["./simulator"]
