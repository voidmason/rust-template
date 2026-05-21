FROM rust:1-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev
COPY . .
RUN cargo build --release

FROM alpine:3
COPY --from=builder /app/target/release/rust-template /app
ENTRYPOINT ["/app"]
