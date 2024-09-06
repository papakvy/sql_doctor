#!/bin/bash

VERSION="1.0.1 (2024-09-06)"

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [OPTIONS] <log_file_path>"
    echo -e "Find SQL queries based on execution time from both compressed and uncompressed log files."

    echo -e "\nOptions:"
    echo -e "  -e, --execution-time <value>"
    echo -e "      The execution time threshold (default: 1000 miliseconds)."
    echo -e "  -p, --total-results-peak <value>"
    echo -e "      The total results peak threshold (default: 200)."
    echo -e "  -m, --multiple-pattern <value>"
    echo -e "      The multiple pattern search (default: n)."
    echo -e "  -h, --help"
    echo -e "      Display this help message."
    echo -e "  -v, --version"
    echo -e "      Display version information."

    exit 0
}

display_version() {
    echo -e "$0 $VERSION"
    exit 0
}

# Function to check if a file exists
check_file_exists() {
    local log_file_path=$1
    if [ ! -f "$log_file_path" ]; then
    printf "\e[1;31mError: File %s not found.\e[0m\n" "$log_file_path"
        exit 0
    fi
}

ensure_multiple_pattern_search() {
    local input=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$input" in
        y|yes) echo "true" ;;
        *) echo "false" ;;
    esac
}

# Function to clear the content of a file
clear_output_file() {
    local output_file=$1
    truncate -s 0 "$output_file"
}

results_temporary_file(){
    local temporary_file_path=$1
    clear_results_temporary_file "$temporary_file_path"
    touch "$temporary_file_path"
}

clear_results_temporary_file(){
    local temporary_file_path=$1
    rm -f "$temporary_file_path"
}

check_file_type() {
    local file_path=$1
    [[ ! -f "$file_path" ]] && echo "not_found" && return

    case "$(file -b --mime-type "$file_path")" in
        text/plain) echo "text" ;;
        application/gzip) echo "gzip" ;;
        *) echo "unknown" ;;
    esac
}

filter_log_data() {
    local execution_time=$1 log_file_path=$2 temporary_file_path=$3
    local log_file_name=$(basename "$log_file_path")
    local file_type=$(check_file_type "$log_file_path")

    local awk_script='
    BEGIN { FS="\\(|\\)"; OFS="" }
    {
        if ($2 ~ /ms/) {
            split($2, a, "[^0-9]+");
            if (a[1] ~ /^[0-9]+(\.[0-9]+)?$/ && a[1] > time) {
                print log_file_name, ":" NR " -- ", $2" -- ", $0
            }
        }
    }'

    local sort_and_format="sort -n -k3,3 | awk -F' -- ' '{print \"🦈 Line \" \$1 \" -- \" \"\033[95m\" \$2 \"\033[0m\"\" -- 👻\", substr(\$0, index(\$0, \$3)) \" 👻\n\"}'"

    case "$file_type" in
        "text")
            awk -v time="$execution_time" -v log_file_name="$log_file_name" "$awk_script" "$log_file_path" | eval "$sort_and_format" >> "$temporary_file_path"
            ;;
        "gzip")
            zcat -f -- "$log_file_path" | awk -v time="$execution_time" -v log_file_name="$log_file_name" "$awk_script" | eval "$sort_and_format" >> "$temporary_file_path"
            ;;
        *)
            echo "Unknown file type: $file_type"
            ;;
    esac
}

filter_log_data_files() {
    local execution_time=$1 log_file_path=$2 temporary_file_path=$3 multiple_pattern=$4

    if [ $(ensure_multiple_pattern_search "$multiple_pattern") = "true" ]; then
        for file in $log_file_path*; do
            [[ -f $file ]] && filter_log_data "$execution_time" "$file" "$temporary_file_path"
        done
    else
        filter_log_data "$execution_time" "$log_file_path" "$temporary_file_path"
    fi
}

# Function to count the total number of results
count_total_results() {
    local temporary_file_path=$1
    cat "$temporary_file_path" | awk 'NF > 0 { count++ } END { print count }'
}

# Function to check if the total results exceed the threshold
check_total_results() {
    local total_results=$1
    local total_results_peak=$2

    if ((total_results > total_results_peak)); then
        read -p $'\e[1;35m• Warning: There are more than \e[1;31m'"$total_results_peak"$'\e[1;35m results. Do you want to continue? (y/n): \e[0m' -r choice
        choice=${choice:-"y"}  # Set default value to "y" if the user presses Enter

        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            printf "\e[1;35m• Script terminated by user.\e[0m\n"
            exit 0
        fi
    fi
}

# Function to display a message when no results are found
display_no_results() {
    local output_file=$1
    local total_results=$2
    local start_time=$3

    if [[ "$total_results" -eq 0 ]]; then
        printf "\e[1;31m• No results found.\e[0m\n"
        display_time_difference "$start_time"
        exit 0;
    fi
}

# Function to display the last 5 results
display_last_3_results() {
    local output_file=$1
    local total_results=$2
    local last_3_results; last_3_results=$(grep -v '^$' "$output_file" | tail -n3)

    printf "• Overview last 3/\e[1;34m%s\e[0m results longest SQL\n\n" "$total_results"
    printf "•••\n%s\n" "$last_3_results"
}

# Function to display the time difference
display_time_difference() {
    local end_time=$SECONDS
    local time_diff=$((end_time - start_time))
    printf "\n\e[1;34mFinished in %s seconds.\e[0m\n" "$time_diff"
}

# Function to display copyright information
display_copyright() {
    printf "\e[3m\e[1;31m_Script created by \e[1;31m©phunt©_\e[1;34m\e[0m\e[0m\n"
}

# Function to process options
process_options() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -e|--execution-time) execution_time="$2"; shift 2 ;;
            -p|--total-results-peak) total_results_peak="$2"; shift 2 ;;
            -m|--multiple-pattern) multiple_pattern="$2"; shift 2 ;;
            -h|--help) display_usage ;;
            -v|--version) display_version ;;
            -*) echo "Invalid option: $1" >&2; echo "See '$0 --help' for more information."; exit 0 ;;
            *) log_file_path=$1; shift 1 ;;
        esac
    done

    # Check if required parameters are provided
    if [[ ! $log_file_path ]]; then
        printf "\e[1;31mError: Please provide the log file path.\e[0m\n"
        echo "See '$0 --help' for more information."
        exit 0
    fi
}

# Function to process log data
process_log_data() {
    local start_time=$SECONDS
    local execution_time=${execution_time:-1000}
    local total_results_peak=${total_results_peak:-200}
    local multiple_pattern=${multiple_pattern:-"n"}

    mkdir -p 'output'
    local temporary_file_path="output/temporary.txt"
    results_temporary_file "$temporary_file_path"

    local output_file_path="output/output_$execution_time.txt"
    clear_output_file "$output_file_path"

    filter_log_data_files "$execution_time" "$log_file_path" "$temporary_file_path" "$multiple_pattern"

    local total_results=$(count_total_results "$temporary_file_path")
    check_total_results "$total_results" "$total_results_peak"

    cp "$temporary_file_path" "$output_file_path"
    display_no_results "$output_file_path" "$total_results" "$start_time"

    printf "• Results written to \e[1;34m$(pwd)/%s\e[0m\n" "$output_file_path"
    display_last_3_results "$output_file_path" "$total_results"

    clear_results_temporary_file "$temporary_file_path"
    display_time_difference "$start_time"
    # display_copyright
}

# Process options
process_options "$@"

# Call the function to process log data
process_log_data "$@"
