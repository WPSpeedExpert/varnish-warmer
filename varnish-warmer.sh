#!/bin/bash
# ==============================================================================
# Script Name:      varnish-warmer.sh
# Description:      A script to warm Varnish cache by crawling sitemap URLs
#                   with rate limiting to prevent server overload
# Author:           WP Speed Expert
# Version:          1.3.0
# Compatibility:    Linux with curl, xmllint
# Requirements:     curl, xmllint, bc
# GitHub URI:       https://github.com/WPSpeedExpert/varnish-warmer
# Cron example:     0 3 * * * /home/onsalenow-grafana/varnish-warmer.sh >> /home/onsalenow-grafana/varnish-warmer.log 2>&1
# ==============================================================================

# Configuration
SITEMAP_URL="https://yourdomain.com/sitemap.xml"
REQUESTS_PER_SECOND=4        # How many requests to make per second
CONCURRENT_REQUESTS=8        # How many concurrent requests to run
USER_AGENT="Varnish-Warmer/1.0 (Cache Warming Bot)"
LOG_FILE="varnish-warming.log"
TEMP_DIR="/tmp/varnish-warmer"

# Create temp directory if it doesn't exist
mkdir -p "${TEMP_DIR}"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Function to check required commands
check_requirements() {
    local required_commands=("curl" "xmllint" "bc")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_message "ERROR: Required commands missing: ${missing_commands[*]}"
        log_message "Please install missing packages and try again."
        exit 1
    fi
}

# Function to handle XML namespace-aware URL extraction
extract_urls() {
    local xml_file="$1"
    local xpath_query="$2"
    
    # Extract URLs and ensure they start with http:// or https://
    xmllint --xpath "//*[local-name()='${xpath_query}']/*[local-name()='loc']/text()" "${xml_file}" 2>/dev/null | \
    tr ' ' '\n' | \
    grep -E '^https?://'
}

# Function to process a single sitemap file
process_sitemap() {
    local sitemap_url="$1"
    local output_file="$2"
    local temp_file="${TEMP_DIR}/temp_sitemap_$$.xml"

    log_message "Processing sitemap: ${sitemap_url}"
    
    # Download sitemap with retry mechanism
    local max_retries=3
    local retry_count=0
    local download_success=false

    while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
        if curl -s -A "${USER_AGENT}" -o "${temp_file}" "${sitemap_url}"; then
            download_success=true
        else
            retry_count=$((retry_count + 1))
            log_message "WARNING: Failed to download sitemap (attempt ${retry_count}/${max_retries})"
            sleep 2
        fi
    done

    if [ "$download_success" = false ]; then
        log_message "ERROR: Failed to download sitemap after ${max_retries} attempts: ${sitemap_url}"
        return 1
    fi

    # Extract URLs and append to output file
    extract_urls "${temp_file}" "url" >> "${output_file}"
    
    local url_count=$(grep -c . "${output_file}")
    log_message "Found ${url_count} URLs in this sitemap"
    
    # Clean up temp file
    rm -f "${temp_file}"
}

# Function to download and parse sitemap
get_urls_from_sitemap() {
    local sitemap_url="$1"
    local temp_file="${TEMP_DIR}/main_sitemap_$$.xml"
    local urls_file="${TEMP_DIR}/urls.txt"

    log_message "Downloading main sitemap from ${sitemap_url}"
    
    # Download main sitemap
    if ! curl -s -A "${USER_AGENT}" -o "${temp_file}" "${sitemap_url}"; then
        log_message "ERROR: Failed to download main sitemap"
        exit 1
    fi

    # Initialize urls file
    > "${urls_file}"

    # Check if this is a sitemap index
    if grep -q "<sitemapindex" "${temp_file}"; then
        log_message "Found sitemap index, processing multiple sitemaps..."
        
        # Extract and process each sitemap URL
        extract_urls "${temp_file}" "sitemap" | while read -r sub_sitemap; do
            process_sitemap "${sub_sitemap}" "${urls_file}"
            sleep 1  # Brief pause between sitemap processing
        done
    else
        log_message "Processing single sitemap..."
        process_sitemap "${sitemap_url}" "${urls_file}"
    fi

    # Ensure we have URLs
    if [ ! -s "${urls_file}" ]; then
        log_message "ERROR: No URLs found in sitemap"
        exit 1
    fi

    # Sort and deduplicate URLs
    sort -u "${urls_file}" -o "${urls_file}"
    
    # Count URLs
    local url_count=$(wc -l < "${urls_file}")
    log_message "Found ${url_count} unique URLs in total"

    # Clean up main sitemap file
    rm -f "${temp_file}"
}

# Function to warm a single URL
warm_url() {
    local url="$1"
    local start_time=$(date +%s.%N)
    
    # Send request with appropriate headers
    local response=$(curl -sL -w "%{http_code}" \
        -A "${USER_AGENT}" \
        -H "X-Cache-Warmup: 1" \
        -o /dev/null \
        "$url")

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    # Log result
    if [ "$response" = "200" ]; then
        log_message "SUCCESS: $url (${duration}s)"
    else
        log_message "FAILED: $url (Status: $response)"
    fi
}

# Function to warm cache with rate limiting
warm_cache() {
    local delay=$(bc <<< "scale=3; 1/${REQUESTS_PER_SECOND}")
    local total_urls=$(wc -l < "${TEMP_DIR}/urls.txt")
    local processed=0
    local success_count=0
    local failed_count=0

    log_message "Starting cache warming with ${REQUESTS_PER_SECOND} req/s (${delay}s delay)"
    log_message "Processing ${total_urls} URLs..."

    # Process URLs in batches
    while IFS= read -r url; do
        ((processed++))
        
        # Start warm_url in background
        warm_url "$url" &
        
        # Limit concurrent processes
        while [ $(jobs -r | wc -l) -ge "$CONCURRENT_REQUESTS" ]; do
            sleep 0.1
        done
        
        # Rate limiting delay
        sleep "$delay"
        
        # Show progress every 100 URLs
        if [ $((processed % 100)) -eq 0 ]; then
            log_message "Progress: ${processed}/${total_urls} URLs processed"
        fi
    done < "${TEMP_DIR}/urls.txt"

    # Wait for remaining background jobs to finish
    wait

    # Calculate success rate
    success_count=$(grep -c "SUCCESS:" "${LOG_FILE}")
    failed_count=$(grep -c "FAILED:" "${LOG_FILE}")
    
    log_message "Cache warming completed. Summary:"
    log_message "Total processed: ${processed}"
    log_message "Successful: ${success_count}"
    log_message "Failed: ${failed_count}"
}

# Trap for cleanup on script exit
cleanup() {
    log_message "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    log_message "Cleanup completed"
}
trap cleanup EXIT

# Main execution
main() {
    log_message "Starting Varnish cache warming process"
    
    # Check requirements
    check_requirements
    
    # Get URLs from sitemap
    get_urls_from_sitemap "${SITEMAP_URL}"
    
    # Warm the cache
    warm_cache
    
    log_message "Process completed successfully"
}

# Run main function
main
