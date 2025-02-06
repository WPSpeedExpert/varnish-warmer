#!/bin/bash
# ==============================================================================
# Script Name:      varnish-warmer.sh
# Description:      A script to warm Varnish cache by crawling sitemap URLs
#                   with rate limiting to prevent server overload
# Author:           WP Speed Expert
# Version:          1.0.0
# Compatibility:    Linux with curl, xmllint
# Requirements:     curl, xmllint, bc
# GitHub URI:       https://github.com/WPSpeedExpert/varnish-warmer
# ==============================================================================

# Configuration
SITEMAP_URL="https://yourdomain.com/sitemap.xml"
REQUESTS_PER_SECOND=2        # How many requests to make per second
CONCURRENT_REQUESTS=4        # How many concurrent requests to run
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

# Function to download and parse sitemap
get_urls_from_sitemap() {
    local sitemap_url="$1"
    local temp_file="${TEMP_DIR}/sitemap.xml"

    log_message "Downloading sitemap from ${sitemap_url}"
    
    # Download sitemap
    if ! curl -s -A "${USER_AGENT}" -o "${temp_file}" "${sitemap_url}"; then
        log_message "ERROR: Failed to download sitemap"
        exit 1
    fi

    # Extract URLs from sitemap
    xmllint --xpath "//xmlns:loc/text()" "${temp_file}" 2>/dev/null | tr ' ' '\n' > "${TEMP_DIR}/urls.txt"
    
    # Count URLs
    local url_count=$(wc -l < "${TEMP_DIR}/urls.txt")
    log_message "Found ${url_count} URLs in sitemap"
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

    log_message "Cache warming completed. Processed ${processed} URLs."
}

# Main execution
main() {
    log_message "Starting Varnish cache warming process"
    
    # Check requirements
    check_requirements
    
    # Get URLs from sitemap
    get_urls_from_sitemap "${SITEMAP_URL}"
    
    # Warm the cache
    warm_cache
    
    # Cleanup
    rm -rf "${TEMP_DIR}"
    
    log_message "Process completed successfully"
}

# Run main function
main
