FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN go build -o simulator ./cmd/server && \
    mkdir -p bin/scenarios && \
    for dir in scenarios/*/; do \
        [ -f "${dir}main.go" ] || continue; \
        name=$(basename "$dir" | sed 's/^[0-9]*-//'); \
        go build -o "bin/scenarios/${name}" "./${dir}"; \
    done

FROM alpine:3.19
RUN apk add --no-cache tzdata
WORKDIR /app
COPY --from=builder /app/simulator .
COPY --from=builder /app/bin ./bin
RUN mkdir -p /app/logs
EXPOSE 8080
CMD ["./simulator"]
