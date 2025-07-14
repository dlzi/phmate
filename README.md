# PHMATE - PHP Built-in Server Manager

PHMATE is a lightweight command-line utility that simplifies management of PHP's built-in web server for local development. It streamlines server startup, configuration, and monitoring with sensible defaults and multiple profile support.

## Features

- **Server Management**: Start, stop, restart, and check status of PHP's built-in web server
- **Interactive Wizard**: Configure server settings via a guided setup with `phmate wizard`
- **Multiple Profiles**: Create and manage different server configurations with the `--profile` option
- **Custom PHP Settings**: Specify PHP binary path and custom php.ini files
- **Router Script Support**: Use custom PHP router script files with auto-detection
- **Auto-Router Detection**: Automatically detects and uses `router.php` in document root if present
- **Configurable Host/Port**: Run servers on custom hostnames and ports
- **Robust Error Handling**: Comprehensive error checking, validation, and detailed logs
- **Logging**: Detailed logs with configurable verbosity levels (DEBUG, INFO, WARNING, ERROR)
- **Status Monitoring**: View running server status including uptime and memory usage

## Requirements

- **Bash**: Version 4.0 or higher
- **PHP**: Version 8.0 or higher with built-in web server support
- **Standard Unix Tools**: ps, kill, netstat/ss (optional for port checking)

## Installation

### Quick Install

1. Download the script:
   ```bash
   curl -o phmate.sh https://raw.githubusercontent.com/dlzi/phmate/main/phmate.sh
   ```

2. Make it executable:
   ```bash
   chmod +x phmate.sh
   ```

3. Optionally, move to a directory in your PATH:
   ```bash
   sudo mv phmate.sh /usr/local/bin/phmate
   ```

### Using Makefile

If you've cloned the repository, you can use the provided Makefile for a complete installation including documentation and bash completion:

```bash
git clone https://github.com/dlzi/phmate.git
cd phmate
make install
```

This will install PHMATE to `/usr/local/bin/phmate` by default. To install to a different location:

```bash
make install PREFIX=~/.local
```

To uninstall PHMATE when installed with the Makefile:

```bash
make uninstall
```

### Using install.sh Script

The repository includes an installation script that properly installs all components including documentation and bash completion:

```bash
git clone https://github.com/dlzi/phmate.git
cd phmate
./install.sh
```

You can customize the installation directories by setting environment variables:

```bash
PREFIX=~/.local ./install.sh
```

To uninstall PHMATE when installed with the install script:

```bash
./uninstall.sh
```

### Package Installation

#### Arch Linux (and derivatives)

For Arch Linux and derivatives (Manjaro, EndeavourOS, etc.), a PKGBUILD is provided:

```bash
git clone https://github.com/dlzi/phmate.git
cd phmate/packages/arch
makepkg -si
```

### Verification

Verify installation:
```bash
phmate version
```

## Usage

PHMATE uses the syntax: `phmate COMMAND [OPTIONS] [<hostname>:<port>]`

### Commands

- **Server Control**:
  - `phmate start [<hostname>:<port>] [options]`: Start the PHP server
  - `phmate stop`: Stop the running server
  - `phmate restart [options]`: Restart the server
  - `phmate status`: Check server status
  - `phmate wizard`: Interactively configure server settings
  - `phmate config`: Display current configuration
  - `phmate help`: Show help information
  - `phmate version`: Display version information

### Options

- `--docroot=<path>`: Set document root directory (default: current directory)
- `--php=<path>`: Specify PHP binary path
- `--php-ini=<path>`: Use custom PHP ini file
- `--profile=<name>`: Use specific configuration profile (default: default)
- `--router=<file>`: Set router script (file path)
- `--debug`: Enable debug logging (sets LOG_LEVEL=DEBUG)

### Auto-Router Detection

PHMATE automatically detects and uses a `router.php` file in the document root directory if:
- No explicit `--router` option is provided
- A `router.php` file exists in the document root

This feature makes it convenient for projects that follow the common convention of using `router.php` as the main routing script.

**Precedence**: Explicit `--router` option always takes precedence over auto-detection.

### Examples

- Start a server on the default host/port (localhost:8000):
  ```bash
  phmate start
  ```

- Start a server on a specific host and port:
  ```bash
  phmate start localhost:8080
  ```

- Use a custom PHP router script (explicit):
  ```bash
  phmate start --router=custom_router.php
  ```

- Start server with auto-detection of router.php:
  ```bash
  phmate start --docroot=/path/to/www
  # Will automatically use /path/to/www/router.php if it exists
  ```

- Start server with a specific document root:
  ```bash
  phmate start --docroot=/path/to/www
  ```

- Use a specific PHP version:
  ```bash
  phmate start --php=/usr/bin/php8.1
  ```

- Use a custom PHP ini file:
  ```bash
  phmate start --php-ini=/etc/php/8.1/php.ini
  ```

- Create and use a named configuration profile:
  ```bash
  phmate start --profile=dev
  ```

- Check server status:
  ```bash
  phmate status
  ```

- Stop the server:
  ```bash
  phmate stop
  ```

- Restart the server:
  ```bash
  phmate restart
  ```

- Configure interactively:
  ```bash
  phmate wizard
  ```

## Configuration

- **Configuration Directory**: `${HOME}/.config/phmate/` (customize with `PHMATE_CONFIG_DIR`)
- **Default Profile**: `${HOME}/.config/phmate/config_default`
- **PID File**: `${HOME}/.config/phmate/phmate.pid`
- **Log Files**: `${HOME}/.config/phmate/phmate.log`
- **Logging Verbosity**: Set `LOG_LEVEL` environment variable (DEBUG, INFO, WARNING, ERROR)

### Profile Behavior

- **Default Profile**: When using the default profile, configuration settings are used for the current session only and **are not saved to disk**. This provides a clean slate for each new server start.
- **Named Profiles**: When using named profiles (e.g., `--profile=dev`), settings are saved to disk at `${HOME}/.config/phmate/config_<profilename>` and persist between sessions.
- **Saving Default Configuration**: To save your preferred default settings, create a named profile and use it consistently.

## Using Router Scripts

### Custom Router Scripts

A custom PHP router script allows you to handle HTTP requests in specific ways, such as routing requests to a single entry point or serving static files directly. Here's a simple example:

```php
<?php
// router.php
if (preg_match('/\.(?:png|jpg|jpeg|gif|css|js)$/', $_SERVER["REQUEST_URI"])) {
    return false; // Serve the requested file as-is
} else {
    include_once 'index.php'; // Route all other requests to index.php
}
```

### Router Script Usage

1. **Auto-Detection**: Place a `router.php` file in your document root and start the server:
   ```bash
   phmate start
   # Automatically detects and uses ./router.php
   ```

2. **Explicit Router**: Specify a custom router script:
   ```bash
   phmate start --router=custom_router.php
   ```

3. **Different Document Root**: Auto-detection works with custom document roots:
   ```bash
   phmate start --docroot=/var/www/html
   # Will use /var/www/html/router.php if it exists
   ```

## Troubleshooting

- **Port Already in Use**: Use `phmate stop` to stop any existing server, or specify a different port
- **Permission Denied**: Ensure the script is executable (`chmod +x phmate.sh`)
- **PHP Not Found**: Specify PHP path with `--php=/path/to/php`
- **PHP Version Too Old**: Update to PHP 8.0+ or install compatible version
- **Log File Access**: Check that the directory `${HOME}/.config/phmate/` is writable
- **Router Script Issues**: Ensure `router.php` has correct PHP syntax and is readable
- **Detailed Errors**: Use `--debug` flag for verbose logging

Check logs for more information:
- PHP logs: `${HOME}/.config/phmate/phmate.log`

## Environment Variables

- `PHMATE_CONFIG_DIR`: Override default configuration directory
- `LOG_LEVEL`: Set logging verbosity (DEBUG, INFO, WARNING, ERROR)

## License

PHMATE is released under the MIT License.

## Author

Developed by Daniel Zilli.