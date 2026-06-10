# SQL Doctor

## Requirements

- `curl` or `wget` for quick install
- Rust toolchain with `cargo` for source builds
- `make` for local development

## Local Testing

```bash
make test
```

## Installation Instructions

### 1. Install

System install to `/usr/local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --system
```

Latest release to `$HOME/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash
```

Specific release:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --version v2.0.3
```

Temporary build from the current `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --from-git main
```

Build and install from source:

```bash
[sudo] make install
```

Custom prefix:

```bash
make install PREFIX="$HOME/.local"
```

If you install to a custom prefix, make sure the target `bin` directory is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Verify

```bash
sql_doctor -v

# sql_doctor 2.0.3 (2026-06-10)
```

### 3. Usage

- Default value: `--execution-time = 1000`, `--top = 15` and `--multiple-pattern = n`

Use the installed command:

```bash
sql_doctor /path/to/log/file.log
```

Or run the development binary from the repository:

```bash
cargo run -- /path/to/log/file.log
```

The previous Bash implementation is kept as `sql_doctor.bash` for comparison and benchmarking:

```bash
./sql_doctor.bash /path/to/log/file.log
```

```bash
sql_doctor -e 5000 /path/to/log/file.log

# Explain
  - Get all SQLs in the `/path/to/log/file.log` with  `--execution-time >= 5000 miliseconds`
```

- Keep only the top N slowest SQLs before sorting the final output. The default is `--top 15`.
```bash
sql_doctor -e 1000 --top 100 /path/to/log/file.log
```

- Include every matching SQL instead of limiting the report to top results.
```bash
sql_doctor -e 1000 --all /path/to/log/file.log
```

### 4. Uninstall

```bash
[sudo] make uninstall
```

If you installed with a custom prefix, uninstall with the same prefix:

```bash
make uninstall PREFIX="$HOME/.local"
```

### 5. Contributing

  - Fork it ( https://github.com/papakvy/sql_doctor/fork )
  - Create your feature branch (`git checkout -b my-new-feature`)
  - Commit your changes (`git commit -am 'Add some feature'`)
  - Push to the branch (`git push origin my-new-feature`)
  - Create a new Pull Request

## Docker

You can build and run SQL Doctor as a container.

### Build locally

```bash
docker build -t sql_doctor .
```

### Run

```bash
docker run --rm -v "$PWD:/data" sql_doctor -e 1000 /data/path/to/logfile.log
```

### Publish on GitHub Container Registry

The repository now includes a GitHub Actions workflow that publishes a Docker image to GHCR when you push a tag like `v1.0.7`.

```bash
docker pull ghcr.io/<owner>/sql_doctor:v1.0.7
```
