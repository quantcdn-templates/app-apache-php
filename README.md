# Apache + PHP Application Template

A production-ready Apache HTTP Server with PHP 8.4 template featuring common extensions, MySQL database support, and Quant integration.

## Features

- **Apache HTTP Server** with mod_php for simple single-container deployment
- **PHP 8.4** with essential extensions (GD, PDO, OPcache, BCMath, etc.)
- **MySQL 8.4** database with optional integration
- **Quant integration** ready out of the box:
  - Client IP handling via `Quant-Client-IP` header
  - Host header override for `Quant-Orig-Host`
  - SMTP relay support for email delivery
  - UID/GID 1000 mapping for EFS compatibility
- **Logging to stdout/stderr** for Docker best practices
- **Composer** included for PHP dependency management
- **Docker & Docker Compose** for containerization

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Git

### Local Development

1. Clone this template:
   ```bash
   git clone <your-repo-url> my-php-app
   cd my-php-app
   ```

2. **Add your PHP application**
   
   Place your PHP application files in the `src/` directory. The template includes a simple demo page that shows system information and tests database connectivity.

3. Copy and configure environment variables:
   ```bash
   cp docker-compose.override.yml.example docker-compose.override.yml
   ```
   
   Edit `docker-compose.override.yml` to set your local environment variables.

4. Start the application:
   ```bash
   docker-compose up -d
   ```

5. Access your application at `http://localhost`

## Configuration

### Environment Variables

Key environment variables you can configure:

#### Database Configuration
- `DB_HOST` - Database host (default: db)
- `DB_PORT` - Database port (default: 3306)
- `DB_DATABASE` - Database name (default: apache_php)
- `DB_USERNAME` - Database username (default: apache_php)
- `DB_PASSWORD` - Database password (default: apache_php)

#### SMTP Configuration
- `QUANT_SMTP_RELAY_ENABLED` - Enable Postfix SMTP relay (default: false)
- `QUANT_SMTP_HOST` - SMTP server hostname
- `QUANT_SMTP_PORT` - SMTP server port (default: 587)
- `QUANT_SMTP_USERNAME` - SMTP authentication username
- `QUANT_SMTP_PASSWORD` - SMTP authentication password
- `QUANT_SMTP_FROM` - From email address
- `QUANT_SMTP_FROM_NAME` - From display name

#### Quant Integration
- `QUANT_ENABLED` - Enable Quant integration
- `QUANT_API_ENDPOINT` - Quant API endpoint
- `QUANT_CUSTOMER` - Your Quant customer ID
- `QUANT_PROJECT` - Your Quant project ID
- `QUANT_TOKEN` - Your Quant API token

#### Debug Configuration
- `QUANT_DEBUG` - Enable Quant debug logging (default: 0)
- `LOG_DEBUG` - Enable general debug logging (default: 0)

### File Storage

The application mounts your local `src/` directory to `/var/www/html` for development. A persistent volume is available at `/var/www/html/data` for application data.

## Development

### PHP Extensions

The following PHP extensions are pre-installed:

- **GD** - Image processing and manipulation
- **OPcache** - PHP bytecode caching for performance
- **PDO MySQL** - MySQL database connectivity
- **PDO PostgreSQL** - PostgreSQL database connectivity
- **ZIP** - Archive handling
- **Redis** - Redis client (extension available, no server included)
- **APCu** - User cache for application-level caching
- **BCMath** - Arbitrary precision mathematics
- **Sockets** - Network socket operations

### Using Composer

Install PHP packages using Composer:

```bash
docker-compose exec apache-php composer require vendor/package
```

### Database Access

Access the MySQL database directly:

```bash
docker-compose exec db mysql -u apache_php -p apache_php
```

### Logs

View application logs:

```bash
docker-compose logs -f apache-php
```

View database logs:

```bash
docker-compose logs -f db
```

## Application Structure

```
app-apache-php/
├── src/                    # Your PHP application files (mounted at /var/www/html)
│   └── index.php          # Demo page with system info
├── quant/                 # Quant integration files
│   ├── entrypoints/       # Startup scripts
│   ├── php.ini.d/         # PHP configuration
│   ├── entrypoints.sh     # Main entrypoint script
│   └── meta.json          # Template metadata
├── Dockerfile             # Container definition
├── docker-compose.yml     # Service orchestration
└── README.md              # This file
```

## Examples

### Simple PHP Application

Create `src/hello.php`:

```php
<?php
echo "<h1>Hello from Apache + PHP!</h1>";
echo "<p>Current time: " . date('Y-m-d H:i:s') . "</p>";
```

### Database Connection

Create `src/db-test.php`:

```php
<?php
try {
    $host = $_ENV['DB_HOST'] ?? 'db';
    $dbname = $_ENV['DB_DATABASE'] ?? 'apache_php';
    $username = $_ENV['DB_USERNAME'] ?? 'apache_php';
    $password = $_ENV['DB_PASSWORD'] ?? 'apache_php';
    
    $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
    echo "Database connection successful!";
} catch (PDOException $e) {
    echo "Connection failed: " . $e->getMessage();
}
```

### Using Environment Variables

```php
<?php
// Database configuration
$dbHost = $_ENV['DB_HOST'] ?? 'localhost';
$dbName = $_ENV['DB_DATABASE'] ?? 'myapp';

// Quant configuration
$quantEnabled = $_ENV['QUANT_ENABLED'] ?? false;
$quantEndpoint = $_ENV['QUANT_API_ENDPOINT'] ?? '';

echo "Database: $dbHost/$dbName<br>";
echo "Quant Enabled: " . ($quantEnabled ? 'Yes' : 'No');
```

## Deployment

This template is designed to work seamlessly with Quant's deployment platform. The Docker container includes all necessary configurations for production deployment.

### Deploying to Quant Cloud

When you fork this repository, you can use the included GitHub Actions workflow to automatically build and deploy your application to Quant Cloud:

1. **Fork this repository** to your GitHub account
2. **Set up GitHub secrets** in your forked repository:
   - `QUANT_API_KEY` - Your Quant Cloud API key
   - `QUANT_ORGANIZATION` - Your Quant organization ID
   - `QUANT_APPLICATION` - Your Quant application ID
3. **Push to branches**:
   - Push to `develop` → deploys to staging environment
   - Push to `main` → deploys to production environment
   - Create tags → deploys tagged versions

The workflow will automatically build your Docker image and deploy it to your Quant Cloud application.

### Key Production Features

1. **Optimized Dockerfile**: Efficient layer caching and minimal image size
2. **Security**: Proper file permissions and security headers
3. **Performance**: OPcache enabled, optimized Apache configuration
4. **Logging**: All logs directed to stdout/stderr for container logging
5. **Health Checks**: Built-in HTTP health check endpoint

## Troubleshooting

### Database Connection Issues

1. Ensure the database container is running:
   ```bash
   docker-compose ps
   ```

2. Check database logs:
   ```bash
   docker-compose logs db
   ```

3. Verify database credentials in your environment configuration.

### File Permission Issues

If you encounter file permission issues with mounted volumes:

```bash
docker-compose exec apache-php chown -R www-data:www-data /var/www/html
```

### Checking PHP Configuration

View PHP configuration:
```bash
docker-compose exec apache-php php -i
```

View loaded extensions:
```bash
docker-compose exec apache-php php -m
```

## License

This Apache + PHP application template is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
