# Runtime is distroless/cc (glibc), so build on a matching Debian glibc:
# bookworm pairs with cc-debian12. Rust version comes from rust-toolchain.toml,
# not the image tag.
FROM rust:1-bookworm AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM gcr.io/distroless/cc-debian12
COPY --from=builder /app/target/release/rust-template /app
ENTRYPOINT ["/app"]
