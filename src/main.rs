use flate2::read::MultiGzDecoder;
use std::cmp::Ordering;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

const VERSION: &str = "1.0.9 (2026-06-10)";
const DEFAULT_EXECUTION_TIME: f64 = 1000.0;
const DEFAULT_TOP_RESULTS: usize = 15;

#[derive(Clone, Debug)]
struct Config {
    execution_time: f64,
    execution_time_label: String,
    multiple_pattern: bool,
    top_results: Option<usize>,
    log_file_path: PathBuf,
}

#[derive(Clone, Debug)]
struct MatchRecord {
    duration_ms: f64,
    duration_label: String,
    location: String,
    raw_log: String,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("\x1b[1;31mError: {error}\x1b[0m");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let started_at = Instant::now();
    let version_check = spawn_version_check();
    let config = parse_args(env::args().collect())?;

    fs::create_dir_all("output")
        .map_err(|error| format!("cannot create output directory: {error}"))?;
    let output_file_path =
        PathBuf::from(format!("output/output_{}.txt", config.execution_time_label));

    let mut records = Vec::new();
    let mut top_records = Vec::new();
    let mut total_matches = 0usize;

    for file_path in input_files(&config)? {
        process_file(
            &file_path,
            &config,
            &mut records,
            &mut top_records,
            &mut total_matches,
        )?;
    }

    if total_matches == 0 {
        println!("\x1b[1;31m• No results found.\x1b[0m");
        print_update_available(version_check);
        println!(
            "\n\x1b[1;34mFinished in {:.2} seconds.\x1b[0m",
            started_at.elapsed().as_secs_f64()
        );
        return Ok(());
    }

    let mut final_records = if config.top_results.is_some() {
        top_records
    } else {
        records
    };

    final_records.sort_by(compare_records);
    write_output(&output_file_path, &final_records)
        .map_err(|error| format!("cannot write {}: {error}", output_file_path.display()))?;

    println!(
        "• Results written to \x1b[1;34m{}\x1b[0m",
        env::current_dir()
            .map_err(|error| format!("cannot read current directory: {error}"))?
            .join(&output_file_path)
            .display()
    );
    display_last_3_results(&final_records);
    print_update_available(version_check);
    println!(
        "\n\x1b[1;34mFinished in {:.2} seconds.\x1b[0m",
        started_at.elapsed().as_secs_f64()
    );

    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    let mut execution_time = DEFAULT_EXECUTION_TIME;
    let mut execution_time_label = trim_number_label(DEFAULT_EXECUTION_TIME.to_string());
    let mut multiple_pattern = false;
    let mut top_results = Some(DEFAULT_TOP_RESULTS);
    let mut log_file_path = None;

    let mut i = 1usize;
    while i < args.len() {
        match args[i].as_str() {
            "-e" | "--execution-time" => {
                let value = option_value(&args, i)?;
                execution_time = parse_positive_number(value, "--execution-time")?;
                execution_time_label = value.to_string();
                i += 2;
            }
            "-m" | "--multiple-pattern" => {
                let value = option_value(&args, i)?;
                multiple_pattern = matches!(value.to_ascii_lowercase().as_str(), "y" | "yes");
                i += 2;
            }
            "-t" | "--top" => {
                let value = option_value(&args, i)?;
                top_results = Some(parse_positive_integer(value, "--top")?);
                i += 2;
            }
            "--all" => {
                top_results = None;
                i += 1;
            }
            "-h" | "--help" => {
                display_usage(&args[0]);
                std::process::exit(0);
            }
            "-v" | "--version" => {
                println!("{} {}", args[0], VERSION);
                std::process::exit(0);
            }
            arg if arg.starts_with('-') => {
                return Err(format!(
                    "Invalid option: {arg}\nSee '{} --help' for more information.",
                    args[0]
                ))
            }
            arg => {
                log_file_path = Some(PathBuf::from(arg));
                i += 1;
            }
        }
    }

    let log_file_path = log_file_path.ok_or_else(|| {
        format!(
            "Please provide the log file path.\nSee '{} --help' for more information.",
            args[0]
        )
    })?;

    Ok(Config {
        execution_time,
        execution_time_label,
        multiple_pattern,
        top_results,
        log_file_path,
    })
}

fn option_value<'a>(args: &'a [String], index: usize) -> Result<&'a str, String> {
    let option = &args[index];
    let value = args
        .get(index + 1)
        .ok_or_else(|| format!("{option} requires a value."))?;
    if value.starts_with('-') {
        return Err(format!("{option} requires a value."));
    }
    Ok(value)
}

fn parse_positive_number(value: &str, option_name: &str) -> Result<f64, String> {
    let parsed = value
        .parse::<f64>()
        .map_err(|_| format!("{option_name} must be a positive number."))?;
    if parsed > 0.0 {
        Ok(parsed)
    } else {
        Err(format!("{option_name} must be greater than 0."))
    }
}

fn parse_positive_integer(value: &str, option_name: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("{option_name} must be a positive integer."))?;
    if parsed > 0 {
        Ok(parsed)
    } else {
        Err(format!("{option_name} must be a positive integer."))
    }
}

fn trim_number_label(value: String) -> String {
    value.trim_end_matches(".0").to_string()
}

fn display_usage(program: &str) {
    println!("Usage: {program} [OPTIONS] <log_file_path>");
    println!(
        "Find SQL queries based on execution time from both compressed and uncompressed log files."
    );
    println!("\nOptions:");
    println!("  -e, --execution-time <value>");
    println!("      The execution time threshold (default: 1000 miliseconds).");
    println!("  -m, --multiple-pattern <value>");
    println!("      The multiple pattern search (default: n).");
    println!("  -t, --top <value>");
    println!("      Keep only the top N slowest queries before sorting (default: 15).");
    println!("  --all");
    println!("      Include all matching queries instead of limiting to top results.");
    println!("  -h, --help");
    println!("      Display this help message.");
    println!("  -v, --version");
    println!("      Display version information.");
}

fn input_files(config: &Config) -> Result<Vec<PathBuf>, String> {
    if !config.multiple_pattern {
        if !config.log_file_path.is_file() {
            return Err(format!(
                "File {} not found.",
                config.log_file_path.display()
            ));
        }
        return Ok(vec![config.log_file_path.clone()]);
    }

    let parent = config
        .log_file_path
        .parent()
        .unwrap_or_else(|| Path::new("."));
    let prefix = config
        .log_file_path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut files = Vec::new();

    for entry in fs::read_dir(parent)
        .map_err(|error| format!("cannot read {}: {error}", parent.display()))?
    {
        let path = entry
            .map_err(|error| format!("cannot read directory entry: {error}"))?
            .path();
        if path.is_file()
            && path
                .file_name()
                .map(|name| name.to_string_lossy().starts_with(&prefix))
                .unwrap_or(false)
        {
            files.push(path);
        }
    }

    files.sort();
    if files.is_empty() {
        Err(format!(
            "No files matched pattern {}*.",
            config.log_file_path.display()
        ))
    } else {
        Ok(files)
    }
}

fn process_file(
    file_path: &Path,
    config: &Config,
    all_records: &mut Vec<MatchRecord>,
    top_records: &mut Vec<MatchRecord>,
    total_matches: &mut usize,
) -> Result<(), String> {
    let file = File::open(file_path)
        .map_err(|error| format!("cannot open {}: {error}", file_path.display()))?;
    let reader: Box<dyn Read> = if is_gzip(file_path)? {
        Box::new(MultiGzDecoder::new(file))
    } else {
        Box::new(file)
    };
    let reader = BufReader::new(reader);
    let log_file_name = file_path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| file_path.display().to_string());

    for (index, line) in reader.lines().enumerate() {
        let line = line.map_err(|error| format!("cannot read {}: {error}", file_path.display()))?;
        if let Some((duration_ms, duration_label)) = parse_duration(&line) {
            if duration_ms > config.execution_time {
                *total_matches += 1;
                let record = MatchRecord {
                    duration_ms,
                    duration_label,
                    location: format!("{}:{}", log_file_name, index + 1),
                    raw_log: line,
                };
                if let Some(limit) = config.top_results {
                    insert_top_record(top_records, record, limit);
                } else {
                    all_records.push(record);
                }
            }
        }
    }

    Ok(())
}

fn is_gzip(file_path: &Path) -> Result<bool, String> {
    let mut file = File::open(file_path)
        .map_err(|error| format!("cannot open {}: {error}", file_path.display()))?;
    let mut magic = [0u8; 2];
    match file.read_exact(&mut magic) {
        Ok(()) => Ok(magic == [0x1f, 0x8b]),
        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => Ok(false),
        Err(error) => Err(format!("cannot inspect {}: {error}", file_path.display())),
    }
}

fn parse_duration(line: &str) -> Option<(f64, String)> {
    let bytes = line.as_bytes();
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == b'(' {
            if let Some(end_offset) = line[index + 1..].find(')') {
                let end = index + 1 + end_offset;
                let inside = &line[index + 1..end];
                if inside.contains("ms") {
                    let numeric = inside.trim_start_matches(|ch: char| !ch.is_ascii_digit());
                    let numeric = numeric
                        .split(|ch: char| !(ch.is_ascii_digit() || ch == '.'))
                        .next()
                        .unwrap_or("");
                    if !numeric.is_empty() {
                        if let Ok(duration_ms) = numeric.parse::<f64>() {
                            return Some((duration_ms, inside.to_string()));
                        }
                    }
                }
                index = end + 1;
            } else {
                break;
            }
        } else {
            index += 1;
        }
    }
    None
}

fn insert_top_record(records: &mut Vec<MatchRecord>, record: MatchRecord, limit: usize) {
    if records.len() < limit {
        records.push(record);
        return;
    }

    if let Some((min_index, min_record)) = records
        .iter()
        .enumerate()
        .min_by(|(_, left), (_, right)| compare_records(left, right))
    {
        if compare_records(&record, min_record) == Ordering::Greater {
            records[min_index] = record;
        }
    }
}

fn compare_records(left: &MatchRecord, right: &MatchRecord) -> Ordering {
    left.duration_ms
        .partial_cmp(&right.duration_ms)
        .unwrap_or(Ordering::Equal)
        .then_with(|| left.location.cmp(&right.location))
}

fn write_output(output_file_path: &Path, records: &[MatchRecord]) -> io::Result<()> {
    let mut output = BufWriter::new(File::create(output_file_path)?);
    for record in records {
        writeln!(
            output,
            "\x1b[1;95m⏰ 【{} (~{:.2}min)】\x1b[0m\t📁 {}\t🦈 {} 🦈",
            record.duration_label,
            record.duration_ms / 60000.0,
            record.location,
            record.raw_log
        )?;
    }
    Ok(())
}

fn display_last_3_results(records: &[MatchRecord]) {
    println!(
        "• Overview last 3/\x1b[1;34m{}\x1b[0m results longest SQL\n",
        records.len()
    );
    println!("•••");
    for record in records
        .iter()
        .rev()
        .take(3)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
    {
        println!(
            "\x1b[1;95m⏰ 【{} (~{:.2}min)】\x1b[0m\t📁 {}\t🦈 {} 🦈",
            record.duration_label,
            record.duration_ms / 60000.0,
            record.location,
            record.raw_log
        );
    }
}

fn spawn_version_check() -> mpsc::Receiver<String> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let output = Command::new("curl")
            .arg("-s")
            .arg("--connect-timeout")
            .arg("1")
            .arg("--max-time")
            .arg("2")
            .arg("https://raw.githubusercontent.com/papakvy/sql_doctor/main/Cargo.toml")
            .output();
        if let Ok(out) = output {
            if out.status.success() {
                if let Ok(content) = String::from_utf8(out.stdout) {
                    for line in content.lines() {
                        if line.trim().starts_with("version =") {
                            if let Some(ver) = line.split('"').nth(1) {
                                let _ = tx.send(ver.trim().to_string());
                                return;
                            }
                        }
                    }
                }
            }
        }
    });
    rx
}

fn print_update_available(rx: mpsc::Receiver<String>) {
    if let Ok(remote_version) = rx.recv_timeout(Duration::from_millis(200)) {
        let current_ver = VERSION.split_whitespace().next().unwrap_or("0.0.0");
        if is_newer_version(current_ver, &remote_version) {
            println!(
                "\n\x1b[1;33m★ A new version of sql_doctor is available: v{} (Current: v{})\x1b[0m",
                remote_version, current_ver
            );
            println!("\x1b[1;33m★ Run the install script to update: curl -fsSL https://raw.githubusercontent.com/papakvy/sql_doctor/main/install.sh | bash\x1b[0m");
        }
    }
}

fn is_newer_version(current: &str, remote: &str) -> bool {
    let parse = |v: &str| -> Vec<u32> {
        v.split('.')
            .map(|s| s.parse::<u32>().unwrap_or(0))
            .collect()
    };
    let current_parts = parse(current);
    let remote_parts = parse(remote);
    remote_parts > current_parts
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_rails_sql_duration() {
        let line = "D, [2026-01-01T00:00:01.000000 #1] DEBUG -- :   (1500.5ms) SELECT slower";
        let parsed = parse_duration(line).expect("duration should parse");
        assert_eq!(parsed.0, 1500.5);
        assert_eq!(parsed.1, "1500.5ms");
    }

    #[test]
    fn ignores_lines_without_duration() {
        assert!(parse_duration("D, [2026] DEBUG -- : SELECT 1").is_none());
    }

    #[test]
    fn keeps_only_top_records() {
        let mut records = Vec::new();
        for duration_ms in [100.0, 300.0, 200.0, 500.0, 400.0] {
            insert_top_record(
                &mut records,
                MatchRecord {
                    duration_ms,
                    duration_label: format!("{duration_ms}ms"),
                    location: format!("log:{duration_ms}"),
                    raw_log: format!("({duration_ms}ms) SELECT 1"),
                },
                3,
            );
        }
        records.sort_by(compare_records);
        let durations: Vec<f64> = records.iter().map(|record| record.duration_ms).collect();
        assert_eq!(durations, vec![300.0, 400.0, 500.0]);
    }

    #[test]
    fn compares_versions_correctly() {
        assert!(is_newer_version("1.0.6", "1.0.9"));
        assert!(is_newer_version("1.0.6", "1.1.0"));
        assert!(is_newer_version("1.0.6", "2.0.0"));
        assert!(!is_newer_version("1.0.9", "1.0.6"));
        assert!(!is_newer_version("1.0.6", "1.0.6"));
    }
}
