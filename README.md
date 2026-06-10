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

Temporary install by building the current `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --from-git main
```

Install from the latest GitHub Release to `$HOME/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash
```

Install a specific release:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --version v1.0.4
```

Install to `/usr/local/bin`. The installer uses `sudo` only when the target directory is not writable:

```bash
curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash -s -- --system
```

Build and install from source:

```bash
[sudo] make install
```

To install into a custom prefix:

```bash
make install PREFIX="$HOME/.local"
```

Make sure the target `bin` directory is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Verify

```bash
sql_doctor -v

# sql_doctor 1.0.4 (2026-06-10)
```

### 3. Usage

  - Default value: `--execution-time = 1000`, `--top = 15`, `--total-results-peak = 200` and `--multiple-pattern = n`

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

- Choose your desired values for `--execution-time` and `--total-results-peak`.
```bash
sql_doctor -e 5000 -p 100 /path/to/log/file.log

# Explain
  - Get all SQLs in the `/path/to/log/file.log` with  `--execution-time >= 5000 miliseconds`
  - Results must be "<=100" records
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
