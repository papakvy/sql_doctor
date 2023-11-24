#!/bin/bash

VERSION="1.0.0 (2023-11-22)"

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [OPTIONS] <log_file_path>"
    echo -e "Compress or uncompress log files with SQL detector."

    echo -e "\nOptions:"
    echo -e "  -e, --execution-time <value>"
    echo -e "      Set the execution time threshold (default: 1000)."
    echo -e "  -p, --total-results-peak <value>"
    echo -e "      Set the total results peak threshold (default: 200)."
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
    local file_path=$1
    if [ ! -f "$file_path" ]; then
        printf "\e[1;31mError: File %s not found.\e[0m\n" "$file_path"
        exit 0
    fi
}

# Function to clear the content of a file
clear_output_file() {
    local output_file=$1
    truncate -s 0 "$output_file"
}

# Function to filter log data based on execution time
filter_log_data() {
    local execution_time=$1
    local log_file_path=$2

    awk -v time="$execution_time" '
    BEGIN { FS="\\(|\\)"; OFS="" }
    {
        if ($2 ~ /ms/) {
            split($2, a, "ms");
            if (a[1] ~ /^[0-9]+(\.[0-9]+)?$/ && a[1] > time) {
                print NR" -- ", a[1]" -- ", $0
            }
        }
    }' "$log_file_path" | sort -n -k3,3 | awk -F' -- ' '{print "🦈 Line " $1 " -- " "\033[95m" $2 " (ms)" "\033[0m"" -- 👻", substr($0, index($0, $3)) "👻\n"}'
}

# Function to count the total number of results
count_total_results() {
    local results=$1
    echo "$results" | awk 'NF > 0 { count++ } END { print count }'
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

# Function to write results to a file
write_results_to_file() {
    local results=$1
    local output_file=$2
    echo "$results" >> "$output_file"
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
display_last_5_results() {
    local output_file=$1
    local total_results=$2
    local last_5_results; last_5_results=$(tail -n7 "$output_file" | grep -v '^$')

    printf "• Overview last 5/\e[1;34m%s\e[0m results longest SQL\n\n" "$total_results"
    printf "•••\n%s\n" "$last_5_results"
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
            -e|--execution-time)
                execution_time="$2"
                shift 2
                ;;
            -p|--total-results-peak)
                total_results_peak="$2"
                shift 2
                ;;
            -h|--help)
                display_usage
                ;;
            -v|--version)
                display_version
                ;;
            -*)
                echo "Invalid option: $1" >&2
                echo "See '$0 --help' for more information."
                exit 0
                ;;
            *)
                log_file_path=$1
                shift 1
                ;;
        esac
    done

    # Check if required parameters are provided
    if [[ ! $log_file_path ]]; then
        printf "\e[1;31mError: Please provide the log file path.\e[0m\n"
        echo "See '$0 --help' for more information."
        exit 0;
    fi
}

# Function to process log data
process_log_data() {
    local start_time=$SECONDS

    check_file_exists "$log_file_path"

    local log_file_path=$log_file_path
    local execution_time=${execution_time:-1000}
    local total_results_peak=${total_results_peak:-200}
    local output_file_path="output.txt"

    clear_output_file "$output_file_path"

    local results; results=$(filter_log_data "$execution_time" "$log_file_path")
    local total_results; total_results=$(count_total_results "$results")

    check_total_results "$total_results" "$total_results_peak"
    write_results_to_file "$results" "$output_file_path"

    display_no_results "$output_file_path" "$total_results" "$start_time" # Exit if no results are found

    printf "• Results written to \e[1;34m$(pwd)/%s\e[0m\n" "$output_file_path"
    display_last_5_results "$output_file_path" "$total_results"
    display_time_difference "$start_time"
    # display_copyright
}

# Process options
process_options "$@"

# Call the function to process log data
process_log_data "$@"
