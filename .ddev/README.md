# DDEV Local Development Setup

This Apache+PHP template includes DDEV configuration for easy local development.

## Quick Start

1. **Install DDEV**: Follow instructions at https://ddev.readthedocs.io/en/stable/users/install/
2. **Start DDEV**: `ddev start`
3. **Access the demo**: DDEV will show you the URL (typically `https://app-apache-php.ddev.site/`)

## What's Included

### Services
- **Web**: PHP 8.4 with Apache-FPM (matches production)
- **Database**: MySQL 8.4 (matches production)

### Configuration Matches Production
- **PHP settings**: Same memory limits as production Dockerfile
- **Environment variables**: Uses `DB_*` variables

### Development Features
- **Xdebug**: Available via `ddev xdebug on`
- **Database**: Import/export via `ddev import-db` / `ddev export-db`

## Common Commands

```bash
# Start/stop
ddev start
ddev stop

# Database operations
ddev import-db --file=backup.sql
ddev export-db > backup.sql

# Debugging
ddev xdebug on
ddev logs -f
```

### Environment Variables
The DDEV setup automatically provides:
- Database connection details

## Production Consistency

This DDEV setup mirrors the production Docker configuration:
- Same PHP version and settings
- Same environment variable handling
- Compatible database settings
