# SQL Doctor

## Pre-requirements

- `shc` package must be installed on your system

## Installation Instructions

### 1. Install

```bash
[sudo] make install
```

Then, follow the messages during installation!

### 2. Verify

```bash
sql_doctor -v

# sql_doctor 1.0.0
```

### 3. Usage

  - Default value: `--execution-time = 1000` and `--total-results-peak = 200`
```bash
sql_doctor /path/to/log/file.log
```

- Choose your desired values for `--execution-time` and `--total-results-peak`.
```bash
sql_doctor -e 5000 -p 100 /path/to/log/file.log

# Explain
  - Get all SQLs in the `/path/to/log/file.log` with  `--execution-time >= 5000 miliseconds`
  - Results must be "<=100" records
```

### 4. Uninstall

```bash
[sudo] make uninstall
```

### 5. Contributing

  - Fork it ( https://github.com/papakvy/sql_doctor/fork )
  - Create your feature branch (`git checkout -b my-new-feature`)
  - Commit your changes (`git commit -am 'Add some feature'`)
  - Push to the branch (`git push origin my-new-feature`)
  - Create a new Pull Request
