FROM rust:1.88-alpine AS builder
WORKDIR /app
# Cài đặt build-base phòng trường hợp cần biên dịch thư viện C (flate2 mặc định dùng pure-Rust nhưng cài sẵn cho chắc chắn)
RUN apk add --no-cache musl-dev
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

FROM alpine:3.20
RUN apk add --no-cache ca-certificates curl
WORKDIR /app
COPY --from=builder /app/target/release/sql_doctor /usr/local/bin/sql_doctor
ENTRYPOINT ["sql_doctor"]
