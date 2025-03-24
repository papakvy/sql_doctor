#!/bin/bash

VERSION="1.0.3 (2024-12-24 🎄)"

# Constants
OUTPUT_DIR="output"
TEMP_FILE="$OUTPUT_DIR/temporary.txt"

# Function to display usage information
display_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <log_file_path>
Find SQL queries based on execution time from both compressed and uncompressed log files.

Options:
  -e, --execution-time <value>
      The execution time threshold (default: 1000 milliseconds).
  -p, --total-results-peak <value>
      The total results peak threshold (default: 200).
  -m, --multiple-pattern <value>
      The multiple pattern search (default: n).  Searches for multiple files matching the pattern.
  -h, --help
      Display this help message.
  -v, --version
      Display version information.
EOF
    exit 0
}

# Function to display version information
display_version() {
    echo "$0 $VERSION"
    exit 0
}

# Function to check if a file exists
check_file_exists() {
    local log_file_path="$1"
    if [[ ! -f "$log_file_path" ]]; then
        printf "\e[1;31mError: File %s not found.\e[0m\n" "$log_file_path"
        exit 1 # Use a non-zero exit code to indicate failure
    fi
}

# Function to convert multiple pattern input to boolean
is_multiple_pattern_search() {
    local input
    input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [[ "$input" == "y" || "$input" == "yes" ]]; then
        return 0  # True
    else
        return 1  # False
    fi
}

# Function to clear the content of a file (using > is simpler and faster)
clear_file() {
    local file_path="$1"
    > "$file_path"
}

# Function to create and optionally clear a temporary file
create_temp_file() {
    local file_path="$1"
    mkdir -p "$(dirname "$file_path")" # Ensure directory exists

    if [[ -f "$file_path" ]]; then
        rm -f "$file_path"
    fi
    touch "$file_path"
}


# Function to determine file type
get_file_type() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "not_found"
        return
    fi

    local mime_type
    mime_type=$(file -b --mime-type "$file_path")

    case "$mime_type" in
        text/plain)
            echo "text"
            ;;
        application/gzip|application/x-gzip)
            echo "gzip"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to extract and filter log data
extract_log_data() {
    local execution_time="$1"
    local log_file_path="$2"
    local temp_file_path="$3"
    local log_file_name file_type

    log_file_name=$(basename "$log_file_path")
    file_type=$(get_file_type "$log_file_path")

    local awk_script='
    BEGIN { FS="\\\\(|\\\\)"; OFS="" }
    $2 ~ /ms/ {
        split($2, a, "[^0-9]+");
        if (a[1] ~ /^[0-9]+(\\.[0-9]+)?$/ && a[1] > time) {
            print log_file_name, ":" NR " -- " $2 " -- " $0
        }
    }'

    local post_process_cmd='awk -F" -- " \'{print $1 " -- " $2, substr($0, index($0, $3))}\''

    case "$file_type" in
        "text")
            awk -v time="$execution_time" -v log_file_name="$log_file_name" "$awk_script" "$log_file_path" |
              eval "$post_process_cmd" >> "$temp_file_path"
            ;;
        "gzip")
            zcat -f -- "$log_file_path" |
              awk -v time="$execution_time" -v log_file_name="$log_file_name" "$awk_script" |
              eval "$post_process_cmd" >> "$temp_file_path"
            ;;
        *)
            echo "Unknown file type: $file_type" >&2 # Send to stderr
            return 1 # Indicate an error
            ;;
    esac
}

# Function to process one or more log files based on a pattern
process_log_files() {
    local execution_time="$1"
    local log_file_path="$2"
    local temp_file_path="$3"
    local multiple_pattern="$4"

    if is_multiple_pattern_search "$multiple_pattern"; then
        # Quote the pattern so the shell doesn't expand it prematurely.
        find . -maxdepth 1 -name "$log_file_path*" -type f -print0 | while IFS= read -r -d $'\0' file; do
           extract_log_data "$execution_time" "$file" "$temp_file_path"
        done
    else
        extract_log_data "$execution_time" "$log_file_path" "$temp_file_path"
    fi

    # Sort, format, and append to the temporary file
    sort -n -k1 -t' ' <(awk '{split($3, a, "ms"); printf "%s %s\n", a[1], $0}' "$temp_file_path") |
      cut -d' ' -f2- |
      awk '{printf "\033[1;95m⏰ 【%s (~%.2fmin)】\033[0m\t📁 %s\t🦈 %s 🦈\n", $3 , $3/60000, $1, substr($0, index($0,$4))}' >> "$temp_file_path".sorted

    mv "$temp_file_path".sorted "$temp_file_path"
}

# Function to count the number of non-empty lines in a file
count_results() {
    local file_path="$1"
    awk 'NF { count++ } END { print count }' "$file_path"
}

# Function to check if the total results exceed the threshold
check_result_threshold() {
    local total_results="$1"
    local total_results_peak="$2"

    if ((total_results > total_results_peak)); then
        read -p $'\e[1;35mWarning: Found \e[1;31m'"$total_results"$'\e[1;35m results. This exceeds the peak threshold of \e[1;31m'"$total_results_peak"$'\e[1;35m results.\nDo you want to continue? (y/n): \e[0m' -r choice

        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

        if [[ "$choice" != "y" && "$choice" != "yes" ]]; then
            printf "\e[1;35m• Script terminated by user.\e[0m\n"
            exit 0
        fi
    fi
}

# Function to display a message when no results are found
handle_no_results() {
    local total_results="$1"
    local start_time="$2"
    local end_time="$3"

    if [[ "$total_results" -eq 0 ]]; then
        printf "\e[1;31m• No results found.\e[0m\n"
        display_time_difference "$start_time" "$end_time"
        exit 0
    fi
}

# Function to display the last N results
display_last_results() {
    local output_file="$1"
    local total_results="$2"
    local num_results="${3:-3}" # Default to 3 if not provided
    local last_results

    last_results=$(tail -n "$num_results" "$output_file")

    printf "• Overview last %s/\e[1;34m%s\e[0m results longest SQL\n\n" "$num_results" "$total_results"
    printf "•••\n%s\n" "$last_results"
}

# Function to calculate and display the time difference
display_time_difference() {
    local start_time="$1"
    local end_time="$2"
    local time_diff=$((end_time - start_time))
    printf "\n\e[1;34mFinished in %s seconds.\e[0m\n" "$time_diff"
}

# Function to display copyright information
display_copyright() {
    printf "\e[3m\e[1;31m_Script created by \e[1;31m©phunt©_\e[1;34m\e[0m\e[0m\n"
}

# Function to parse command-line options
parse_options() {
    execution_time=1000
    total_results_peak=200
    multiple_pattern="n"
    log_file_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--execution-time)
                execution_time="$2"
                shift 2
                ;;
            -p|--total-results-peak)
                total_results_peak="$2"
                shift 2
                ;;
            -m|--multiple-pattern)
                multiple_pattern="$2"
                shift 2
                ;;
            -h|--help)
                display_usage
                exit 0
                ;;
            -v|--version)
                display_version
                exit 0
                ;;
            --) # End of options
                shift
                break
                ;;
            -*)
                echo "Invalid option: $1" >&2
                echo "See '$0 --help' for more information." >&2
                exit 1
                ;;
            *)
                log_file_path="$1"
                shift
                ;;
        esac
    done

    # Check for required parameters
    if [[ -z "$log_file_path" ]]; then
        printf "\e[1;31mError: Please provide the log file path.\e[0m\n" >&2
        echo "See '$0 --help' for more information." >&2
        exit 1
    fi
}

# Main function to orchestrate the log processing
main() {
    parse_options "$@"

    local start_time=$SECONDS
    local output_file="$OUTPUT_DIR/output_$execution_time.txt"


    create_temp_file "$TEMP_FILE"  # Create temporary file
    clear_file "$output_file"       # Clear output file

    process_log_files "$execution_time" "$log_file_path" "$TEMP_FILE" "$multiple_pattern"

    local end_time=$SECONDS
    local total_results=$(count_results "$TEMP_FILE")

    check_result_threshold "$total_results" "$total_results_peak"
    handle_no_results "$total_results" "$start_time" "$end_time"


    mv "$TEMP_FILE" "$output_file" # Atomic rename
    printf "• Results written to \e[1;34m%s\e[0m\n" "$(pwd)/$output_file"

    display_last_results "$output_file" "$total_results"

    display_time_difference "$start_time" "$end_time"
    display_copyright
}

# Run the main function with all arguments passed to the script
main "$@"
