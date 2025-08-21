# Quant PHP Configuration

This directory contains PHP configuration files that are automatically copied to `/usr/local/etc/php/conf.d/` during Docker image build.

## Included Files

- **99-quant-logging.ini** - Suppresses PHP warnings and notices while preserving fatal errors

## Adding Custom PHP Configuration

To add custom PHP settings:

1. Create a new `.ini` file in this directory (e.g., `90-my-custom.ini`)
2. Add your PHP configuration directives:
   ```ini
   ; My custom PHP settings
   memory_limit = 512M
   max_execution_time = 300
   ```
3. Rebuild your Docker image

Files are loaded in alphabetical order, so use numeric prefixes to control loading sequence:
- `10-` - Loads first
- `50-` - Loads in middle  
- `99-` - Loads last (like our logging config)

## PHP Configuration Reference

Common settings you might want to customize:
- `memory_limit` - Maximum memory per script
- `max_execution_time` - Maximum execution time in seconds
- `upload_max_filesize` - Maximum file upload size
- `post_max_size` - Maximum POST data size
- `max_input_vars` - Maximum input variables