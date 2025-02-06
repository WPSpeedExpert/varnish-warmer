<div align="center">
  <img src="banner.svg" alt="Varnish Cache Warmer" width="800">
</div>

# Varnish Cache Warmer

A high-performance bash script for warming Varnish cache by crawling XML sitemaps. Designed to efficiently preload your cache while being mindful of server resources.

## Quick Start

```bash
./varnish-warmer.sh --sitemap https://example.com/sitemap.xml
```

## Features

- Rate limiting to prevent server overload
- Concurrent request processing
- Smart XML sitemap parsing
- Real-time progress tracking
- Comprehensive error handling
- Resource-friendly design
- Highly configurable

## Requirements

- Linux/Unix environment
- Bash shell
- Required packages:
  - `curl`
  - `libxml2-utils`
  - `bc`

## Installation

Clone this repository:

```bash
git clone https://github.com/yourusername/varnish-warmer.git
cd varnish-warmer
```

Make the script executable:

```bash
chmod +x varnish-warmer.sh
```

Install required dependencies:

For Debian/Ubuntu:

```bash
sudo apt-get install curl libxml2-utils bc
```

For CentOS/RHEL:

```bash
sudo yum install curl libxml2 bc
```

## Configuration

Edit the following variables in the script to match your environment:

```bash
SITEMAP_URL="https://yourdomain.com/sitemap.xml"
REQUESTS_PER_SECOND=2        # Adjust based on server capacity
CONCURRENT_REQUESTS=4        # Adjust based on server capacity
USER_AGENT="Varnish-Warmer/1.0 (Cache Warming Bot)"
LOG_FILE="varnish-warming.log"
TEMP_DIR="/tmp/varnish-warmer"
```

## Usage

Run the script manually:

```bash
./varnish-warmer.sh
```

For automated running, add to crontab:

```bash
# Run daily at 3 AM
0 3 * * * /path/to/varnish-warmer.sh
```

```bash
# Run daily at 3 AM
0 3 * * * /path/to/varnish-warmer.sh >> /var/log/varnish-warmer.log 2>&1
```

## Log Output

The script creates a detailed log file with timestamps:

```
[2025-02-06 10:00:01] Starting Varnish cache warming process
[2025-02-06 10:00:01] Downloading sitemap from https://yourdomain.com/sitemap.xml
[2025-02-06 10:00:02] Found 1500 URLs in sitemap
[2025-02-06 10:00:02] Starting cache warming with 2 req/s (0.500s delay)
[2025-02-06 10:00:02] Processing 1500 URLs...
[2025-02-06 10:00:32] Progress: 100/1500 URLs processed
```

## Performance Tuning

Adjust these parameters based on your server's capacity:

### REQUESTS_PER_SECOND

- Start low (2-3)
- Monitor server load
- Increase gradually if server handles it well

### CONCURRENT_REQUESTS

- Default: 4
- Increase for better performance on powerful servers
- Decrease if experiencing issues

## Best Practices

- Run during off-peak hours
- Monitor server load during execution
- Adjust rate limiting based on server capacity
- Keep logs for troubleshooting
- Regularly check for script updates

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
