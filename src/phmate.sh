#!/bin/bash
#
# PHMATE - PHP Built-in Server Manager.
# A lightweight tool to manage PHP's built-in web server for local development.
#
# Copyright (C) 2025, Daniel Zilli. All rights reserved.
#

# Exit on error, undefined vars, and error in pipes.
set -euo pipefail

# --- Default Configuration & Constants ---

HOST="localhost"
PORT="8000"
ROUTER=""
DOC_ROOT="."
VERSION="1.1.0"
PROFILE="default"
CONFIG_DIR="${PHMATE_CONFIG_DIR:-${HOME}/.config/phmate}"
CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
PIDFILE="${CONFIG_DIR}/phmate.pid"
LOGFILE="${CONFIG_DIR}/phmate.log"
PHP_INI=""
PHP_BIN="php"

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
: "${LOG_LEVEL:=INFO}" # Default log level

declare -r COLOR_INFO='\033[0;34m'    # Blue
declare -r COLOR_SUCCESS='\033[0;32m' # Green
declare -r COLOR_WARNING='\033[0;33m' # Yellow
declare -r COLOR_ERROR='\033[0;31m'   # Red
declare -r COLOR_RESET='\033[0m'      # Reset color

mkdir -p "${CONFIG_DIR}" 2> /dev/null || {
    printf "[ERROR] Failed to create configuration directory: %s\n" "${CONFIG_DIR}" >&2
    exit 1
}

# --- Core Functions ---

# Function: logs a message to a file and outputs it to the console.
log_message() {
    # Input parameters
    local level="$1"
    local message="$2"

    # Validate log level
    local current_level_val="${LOG_LEVELS[${level^^}]:-${LOG_LEVELS[ERROR]}}"
    local configured_level_val="${LOG_LEVELS[${LOG_LEVEL^^}]:-${LOG_LEVELS[INFO]}}"
    if [[ "$current_level_val" -lt "$configured_level_val" ]]; then
        return 0
    fi

    # Prepare metadata
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2> /dev/null) || timestamp="UNKNOWN_TIME"
    local pid=$$

    # Format message for console output
    local formatted
    case "${level^^}" in
        INFO) formatted=$(printf "%s[INFO]%s %s" "$COLOR_INFO" "$COLOR_RESET" "$message") ;;
        SUCCESS) formatted=$(printf "%s[SUCCESS]%s %s" "$COLOR_SUCCESS" "$COLOR_RESET" "$message") ;;
        WARNING) formatted=$(printf "%s[WARNING]%s %s" "$COLOR_WARNING" "$COLOR_RESET" "$message") ;;
        ERROR) formatted=$(printf "%s[ERROR]%s %s" "$COLOR_ERROR" "$COLOR_RESET" "$message") ;;
        DEBUG) formatted=$(printf "[DEBUG] %s" "$message") ;;
        *) formatted=$(printf "%s" "$message") ;;
    esac

    # Write to log file
    printf "[%s] [%s] [PID:%d] %s\n" "$timestamp" "${level^^}" "$pid" "$message" >> "$LOGFILE" 2> /dev/null || {
        printf "[%s] [WARNING] [PID:%d] Failed to write to log file: %s\n" "$timestamp" "$pid" "$LOGFILE" >&2
    }

    # Output to console
    local output_stream=1
    [[ "${level^^}" == "ERROR" || "${level^^}" == "WARNING" ]] && output_stream=2
    if [[ -t "$output_stream" ]]; then
        echo -e "$formatted" >&"$output_stream"
    else
        echo -e "$formatted" | sed 's/\x1b\[[0-9;]*m//g' >&"$output_stream"
    fi
}

# Function: manages PID file operations.
# Function: manages PID file operations.
manage_pidfile() {
    # Input parameters
    local action="$1"
    local extra_data="${2:-}"

    case "$action" in
        create)
            # Resolve absolute paths
            local abs_doc_root
            abs_doc_root=$(realpath -m "$DOC_ROOT" 2> /dev/null) || abs_doc_root="$DOC_ROOT"
            local abs_router=""
            
            # Handle auto-detected router
            if [ -n "$ROUTER" ]; then
                abs_router=$(realpath -m "$ROUTER" 2> /dev/null) || abs_router="$ROUTER"
            else
                # Check for auto-detected router.php in document root
                local auto_router="$abs_doc_root/router.php"
                if [ -f "$auto_router" ]; then
                    abs_router="$auto_router"
                fi
            fi

            # Create PID file with server info
            if ! cat > "$PIDFILE" << EOF; then
HOST=$HOST
PORT=$PORT
DOC_ROOT=$abs_doc_root
ROUTER=$abs_router
PID=$extra_data
PROFILE=$PROFILE
EOF
                log_message "ERROR" "Failed to write PID file: $PIDFILE"
                return 1
            fi

            # Set file permissions
            chmod 600 "$PIDFILE" 2> /dev/null || log_message "WARNING" "Failed to set permissions on PID file: $PIDFILE"
            return 0
            ;;

        read)
            # Check if PID file exists
            if [ ! -e "$PIDFILE" ]; then
                return 1
            fi

            # Read and validate PID file content
            local content
            content=$(cat "$PIDFILE")
            if ! echo "$content" | grep -qE '^(HOST|PORT|DOC_ROOT|ROUTER|PID|PROFILE)=' \
                || ! echo "$content" | grep -q '^PID=' \
                || ! echo "$content" | grep -q '^HOST=' \
                || ! echo "$content" | grep -q '^PORT='; then
                log_message "ERROR" "PID file has invalid format: $PIDFILE"
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                return 1
            fi

            # Output valid content
            echo "$content"
            return 0
            ;;

        get_value)
            # Extract specific value from PID file
            local pid_data
            pid_data=$(manage_pidfile read) || return 1
            echo "$pid_data" | grep "^${extra_data}=" | cut -d'=' -f2
            return 0
            ;;

        check)
            # Read PID file
            local pid_data server_pid
            pid_data=$(manage_pidfile read) || return 1
            server_pid=$(echo "$pid_data" | grep '^PID=' | cut -d'=' -f2)

            # Validate PID
            if [ -z "$server_pid" ] || ! [[ "$server_pid" =~ ^[0-9]+$ ]]; then
                log_message "WARNING" "Invalid PID in $PIDFILE"
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                return 1
            fi

            # Check if process exists
            if ! kill -0 "$server_pid" 2> /dev/null; then
                log_message "WARNING" "PHP server process (PID: $server_pid) not found."
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed stale PID file: $PIDFILE"
                return 1
            fi

            # Validate port binding if lsof is available
            if command -v lsof > /dev/null 2>&1; then
                local port
                port=$(echo "$pid_data" | grep '^PORT=' | cut -d'=' -f2)
                if ! lsof -i :"$port" -sTCP:LISTEN -t 2> /dev/null | grep -q "^$server_pid$"; then
                    log_message "WARNING" "PID $server_pid does not match process on port $port."
                    rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                    return 1
                fi
            fi
            return 0
            ;;

        cleanup)
            # Remove PID file
            rm -f "$PIDFILE" 2> /dev/null
            return 0
            ;;
    esac

    # Invalid action
    return 1
}

# Function: display usage information.
usage() {
    cat << EOF

PHMATE - PHP Built-in Server Manager

Usage:
    phmate <command> [options] [<hostname>:<port>]

Commands:
    start     Start the PHP server (default: localhost:8000)
    stop      Stop the running server
    restart   Restart the server
    status    Show server status
    wizard    Interactive setup to configure server settings
    config    Show current configuration
    help      Display this help information
    version   Show version information

Options:
    --docroot=<path>     Set document root directory
    --php=<path>         Specify PHP binary path
    --php-ini=<path>     Specify custom PHP ini file
    --profile=<name>     Use specific configuration profile
    --router=<file>      Set router script (file path)
    --debug              Enable debug logging (sets LOG_LEVEL=DEBUG)

Router Script Auto-Detection:
    If no --router option is specified, PHMATE will automatically look for
    'router.php' in the document root directory and use it if found.

Examples:
    phmate start localhost:8080
    phmate start --router=custom_router.php
    phmate start --docroot=/path/to/www --profile=dev
    phmate start --php=/usr/bin/php8.1 --php-ini=/etc/php/8.1/php.ini
    phmate stop
    phmate wizard --profile=dev

Environment Variables:
    PHMATE_CONFIG_DIR   Override default config directory (~/.config/phmate)
    LOG_LEVEL           Set logging verbosity (DEBUG, INFO, WARNING, ERROR)

EOF
}
# Function: display version information.
show_version() {
    echo "PHMATE - PHP Built-in Server Manager"
    echo "Version: ${VERSION}"
    echo "Author: Daniel Zilli"
}

# --- Validation Functions ---

# Function: validates if a file or directory exists.
validate_path() {
    # Input parameters
    local path="$1"
    local type="$2" # "file" or "dir"
    local description="$3"

    # Check for empty path
    [[ -z "$path" ]] && return 0

    # Validate path based on type
    if [[ "$type" == "file" && ! -f "$path" ]]; then
        log_message "ERROR" "$description '$path' not found."
        return 1
    elif [[ "$type" == "dir" && ! -d "$path" ]]; then
        log_message "ERROR" "$description '$path' not found."
        return 1
    fi

    # Path is valid
    return 0
}

# Function: validates hostname format.
validate_hostname() {
    # Input parameter
    local hostname="$1"

    # Validate hostname format
    if [[ "$hostname" =~ ^[a-zA-Z0-9.-]+$ || "$hostname" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ || "$hostname" =~ ^\[[0-9a-fA-F:]+\]$ ]]; then
        return 0
    fi

    # Log error for invalid hostname
    log_message "ERROR" "Invalid hostname: $hostname"
    return 1
}

# Function: validates port number.
validate_port() {
    # Input parameter
    local port="$1"

    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_message "ERROR" "Invalid port number: $port"
        return 1
    fi

    # Port is valid
    return 0
}

# Function: validates PHP installation and version.
validate_php() {
    # Input parameter
    local php_cmd="${PHP_BIN:-php}"
    log_message "DEBUG" "Validating PHP installation: $php_cmd"

    # Find PHP binary path
    local php_cmd_path
    php_cmd_path=$(type -P "$php_cmd" 2> /dev/null) || {
        log_message "ERROR" "PHP binary not found using command '$php_cmd'. Please install PHP 8.0 or higher, or specify path with --php."
        return 1
    }

    # Update PHP_BIN with resolved path if default was used
    if [ "$PHP_BIN" = "php" ] || [ -z "$PHP_BIN" ]; then
        PHP_BIN="$php_cmd_path"
    fi

    # Check if built-in server is supported
    if ! "$php_cmd_path" --help 2> /dev/null | grep -q -- '-S'; then
        log_message "ERROR" "PHP at '$php_cmd_path' does not support the built-in web server."
        return 1
    fi

    # Check PHP version
    local php_version
    php_version=$("$php_cmd_path" -v 2> /dev/null | grep -oE 'PHP [0-9]+\.[0-9]+\.[0-9]+' | cut -d' ' -f2) || {
        log_message "ERROR" "Failed to retrieve PHP version from '$php_cmd_path'."
        return 1
    }

    # Compare version
    if ! compare_version "$php_version" "8.0.0"; then
        log_message "ERROR" "PHP version $php_version is too old. Required: 8.0.0"
        return 1
    fi

    # PHP is valid
    return 0
}

# Function: checks if a port is available on a host.
check_port_available() {
    # Input parameters
    local host="$1"
    local port="$2"
    log_message "DEBUG" "Checking port $port availability on host $host"

    # Check port using ss (preferred)
    if command -v ss > /dev/null 2>&1; then
        if ss -tuln | grep -qE "($host|0.0.0.0|\[::\]):$port\s"; then
            log_message "ERROR" "Port $host:$port is in use."
            return 1
        fi
    # Fallback to lsof
    elif command -v lsof > /dev/null 2>&1; then
        if lsof -i :"$port" -sTCP:LISTEN > /dev/null 2>&1; then
            log_message "ERROR" "Port $host:$port is in use."
            return 1
        fi
    # No tools available
    else
        log_message "ERROR" "No port checking tool (ss or lsof) available. Cannot reliably verify if port $host:$port is free. Install 'ss' (part of iproute2) or 'lsof' to ensure accurate port checking, or proceed at risk of port conflicts."
        return 1 # Fail to prevent potential conflicts
    fi

    # Port is available
    return 0
}

# Function: compares two version strings.
compare_version() {
    # Input parameters
    local version="$1"
    local min_version="$2"

    # Compare versions
    if [ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" = "$min_version" ]; then
        return 0
    fi

    # Version is less than minimum
    return 1
}

# --- Configuration Management ---

# Function: parses hostname:port from argument.
parse_hostport() {
    # Input parameter
    local hostport_arg="$1"
    log_message "DEBUG" "Parsing hostport: $hostport_arg"

    # Parse input based on format
    if [[ "$hostport_arg" =~ ^([^:]+):([0-9]+)$ ]]; then
        # Format: host:port
        local parsed_host="${BASH_REMATCH[1]}"
        local parsed_port="${BASH_REMATCH[2]}"
        validate_hostname "$parsed_host" || return 1
        validate_port "$parsed_port" || return 1
        HOST="$parsed_host"
        PORT="$parsed_port"
    elif [[ "$hostport_arg" =~ ^:([0-9]+)$ ]]; then
        # Format: :port
        local parsed_port="${BASH_REMATCH[1]}"
        validate_port "$parsed_port" || return 1
        PORT="$parsed_port"
    elif [[ "$hostport_arg" =~ ^([^:]+):?$ ]]; then
        # Format: host: or just host
        local parsed_host="${BASH_REMATCH[1]}"
        validate_hostname "$parsed_host" || return 1
        HOST="$parsed_host"
    elif [[ "$hostport_arg" =~ ^[0-9]+$ ]]; then
        # Format: just port number
        validate_port "$hostport_arg" || return 1
        PORT="$hostport_arg"
    else
        # Invalid format
        log_message "WARNING" "Could not parse '$hostport_arg' as host:port. Using defaults: $HOST:$PORT"
    fi

    # Log result
    log_message "DEBUG" "Parsed host:port as HOST=$HOST, PORT=$PORT"
    return 0
}

# Function: parses command line options.
parse_options() {
    # Initialize variables
    local arg params=()

    # Process command line options
    while [ "$#" -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --docroot=*)
                DOC_ROOT="${arg#*=}"
                validate_path "$DOC_ROOT" "dir" "Document root directory" || return 1
                shift
                ;;
            --php=*)
                PHP_BIN="${arg#*=}"
                shift
                ;;
            --php-ini=*)
                PHP_INI="${arg#*=}"
                validate_path "$PHP_INI" "file" "PHP ini file" || return 1
                shift
                ;;
            --profile=*)
                PROFILE="${arg#*=}"
                CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
                shift
                ;;
            --router=*)
                ROUTER="${arg#*=}"
                [[ -n "$ROUTER" ]] && validate_path "$ROUTER" "file" "Router script" || return 1
                shift
                ;;
            --debug)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -*)
                log_message "ERROR" "Unknown option: $arg"
                usage
                return 2
                ;;
            *)
                params+=("$arg")
                shift
                ;;
        esac
    done

    # Process positional arguments (hostname:port)
    if [[ "${#params[@]}" -gt 0 ]]; then
        parse_hostport "${params[0]}" || return 1
    fi

    # Options parsed successfully
    return 0
}

# Function: loads configuration from file.
load_config() {
    # Initialize configuration file path
    local config_file="${CONFIG_DIR}/config_${PROFILE:-default}"
    log_message "DEBUG" "Loading configuration from: $config_file"

    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR" 2> /dev/null || {
        log_message "ERROR" "Failed to create config directory: $CONFIG_DIR"
        return 1
    }
    chmod 700 "$CONFIG_DIR" 2> /dev/null || log_message "WARNING" "Failed to set permissions on config directory"

    # Load configuration if file exists
    if [ -f "$config_file" ]; then
        # Set file permissions
        chmod 600 "$config_file" 2> /dev/null || log_message "WARNING" "Failed to set permissions on config file"

        # Validate config file syntax
        if ! bash -n "$config_file" 2> /dev/null; then
            log_message "ERROR" "Invalid syntax in configuration file: $config_file"
            return 1
        fi

        # Source the configuration
        # shellcheck source=/dev/null
        if ! source "$config_file"; then
            log_message "ERROR" "Failed to load configuration from: $config_file"
            return 1
        fi
        log_message "DEBUG" "Loaded configuration from file"
    else
        log_message "DEBUG" "No configuration file found, using defaults."
    fi

    # Update global config file variable
    CONFIG_FILE="$config_file"

    # Configuration loaded successfully
    return 0
}

# Function: saves current configuration to file.
save_config() {
    # Log save operation
    log_message "DEBUG" "Saving configuration to $CONFIG_FILE"

    # Ensure config directory exists
    mkdir -p "$(dirname "$CONFIG_FILE")" || {
        log_message "ERROR" "Failed to create config directory: $(dirname "$CONFIG_FILE")"
        return 1
    }

    # Resolve absolute paths
    local abs_doc_root
    abs_doc_root=$(realpath -m "$DOC_ROOT" 2> /dev/null) || abs_doc_root="$DOC_ROOT"
    local abs_router=""
    [[ -n "$ROUTER" ]] && abs_router=$(realpath -m "$ROUTER" 2> /dev/null) || abs_router="$ROUTER"
    local abs_php_ini=""
    [[ -n "$PHP_INI" ]] && abs_php_ini=$(realpath -m "$PHP_INI" 2> /dev/null) || abs_php_ini="$PHP_INI"

    # Write configuration to file
    if ! cat > "$CONFIG_FILE" << EOF; then
# PHMATE Configuration for profile: $PROFILE
HOST="$HOST"
PORT="$PORT"
DOC_ROOT="$abs_doc_root"
ROUTER="$abs_router"
PHP_BIN="$PHP_BIN"
PHP_INI="$abs_php_ini"
EOF
        log_message "ERROR" "Failed to save configuration to $CONFIG_FILE."
        return 1
    fi

    # Set file permissions
    chmod 600 "$CONFIG_FILE" || log_message "WARNING" "Failed to set permissions on config file"

    # Log success
    log_message "DEBUG" "Configuration saved successfully"

    # Configuration saved successfully
    return 0
}

# Function: show current configuration.
show_config() {
    printf "Current Configuration (%s):\n" "$PROFILE"
    printf "  %-15s %s\n" "Profile:" "$PROFILE"
    printf "  %-15s %s\n" "Hostname:" "$HOST"
    printf "  %-15s %s\n" "Port:" "$PORT"
    printf "  %-15s %s\n" "Document root:" "$DOC_ROOT"
    printf "  %-15s %s\n" "Router script:" "${ROUTER:-None}"
    printf "  %-15s %s\n" "PHP binary:" "${PHP_BIN:-Default (php)}"
    printf "  %-15s %s\n" "PHP ini file:" "${PHP_INI:-Default}"
    printf "  %-15s %s\n" "Log Level:" "$LOG_LEVEL"
}

# --- Server Management ---

# Function: finds processes listening on a specified port.
find_port_processes() {
    # Input parameter
    local port="$1"
    local pids=()

    # Check for available tools and find PIDs
    if command -v lsof > /dev/null 2>&1; then
        mapfile -t pids < <(lsof -i :"$port" -sTCP:LISTEN -t 2> /dev/null)
    elif command -v ss > /dev/null 2>&1; then
        mapfile -t pids < <(ss -tuln | grep -w "$port" | awk '{print $NF}' | grep -o '[0-9]\+' | sort -u)
    fi

    # Output found PIDs
    echo "${pids[@]}"
}

# Function: starts the PHP server.
start_server() {
    # Validate PHP installation
    validate_php || return 1

    # Check port availability
    check_port_available "$HOST" "$PORT" || return 1

    # Resolve and validate document root
    local abs_doc_root
    abs_doc_root=$(realpath -m "$DOC_ROOT" 2> /dev/null) || abs_doc_root="$DOC_ROOT"
    validate_path "$abs_doc_root" "dir" "Document root" || return 1

    # Auto-detect router.php in document root if no router is explicitly specified
    local router_script_arg=""
    if [ -n "${ROUTER:-}" ]; then
        # Explicit router specified - validate and use it
        local abs_router
        abs_router=$(realpath -m "$ROUTER" 2> /dev/null) || abs_router="$ROUTER"
        validate_path "$abs_router" "file" "Router script" || return 1
        router_script_arg="$abs_router"
        log_message "INFO" "Using explicit router script: $abs_router"
    else
        # No explicit router - check for router.php in document root
        local auto_router="$abs_doc_root/router.php"
        if [ -f "$auto_router" ]; then
            router_script_arg="$auto_router"
            log_message "INFO" "Auto-detected router script: $auto_router"
        else
            log_message "DEBUG" "No router.php found in document root: $abs_doc_root"
        fi
    fi

    # Resolve and validate PHP ini file if provided
    local php_ini_arg=""
    if [ -n "${PHP_INI:-}" ]; then
        local abs_php_ini
        abs_php_ini=$(realpath -m "$PHP_INI" 2> /dev/null) || abs_php_ini="$PHP_INI"
        validate_path "$abs_php_ini" "file" "PHP ini file" || return 1
        php_ini_arg="-c $abs_php_ini"
    fi

    # Prepare and validate log file
    touch "$LOGFILE" 2> /dev/null || {
        log_message "ERROR" "Cannot write to PHP log file: $LOGFILE"
        return 1
    }
    chmod 600 "$LOGFILE" 2> /dev/null || log_message "WARNING" "Failed to set permissions on log file"

    # Check for existing server
    if manage_pidfile check; then
        log_message "WARNING" "PHP server is already running. Use 'phmate restart' or stop it first."
        return 1
    fi

    # Build server command
    local start_command="${PHP_BIN} ${php_ini_arg} -S ${HOST}:${PORT} -t ${abs_doc_root}"
    [[ -n "$router_script_arg" ]] && start_command="${start_command} ${router_script_arg}"

    # Log server start details with better formatting
    log_message "INFO" "Starting PHP server at http://${HOST}:${PORT}/"
    log_message "INFO" "- Document root: ${abs_doc_root}"
    if [ -n "$router_script_arg" ]; then
        local router_name
        router_name=$(basename "$router_script_arg")
        if [ "$router_script_arg" = "$abs_doc_root/$router_name" ] && [ "$router_name" = "router.php" ]; then
            log_message "INFO" "- Router: ${router_name} (auto-detected)"
        else
            log_message "INFO" "Router: ${router_name} (${router_script_arg})"
        fi
    else
        log_message "DEBUG" "No router script configured"
    fi

    # Start server in background
    eval "${start_command} >> \"${LOGFILE}\" 2>&1 &"
    local server_pid=$!

    # Verify server process
    if ! kill -0 "$server_pid" 2> /dev/null; then
        log_message "ERROR" "Failed to start PHP server. Check logs: $LOGFILE"
        return 1
    fi

    # Create PID file
    if ! manage_pidfile create "$server_pid"; then
        log_message "ERROR" "Failed to create PID file"
        kill "$server_pid" 2> /dev/null
        return 1
    fi

    # Verify server is listening on port (retry up to 3 times, 1 second apart)
    local attempt=0 max_attempts=3
    local port_bound=0
    while [ "$attempt" -lt "$max_attempts" ]; do
        if command -v lsof > /dev/null 2>&1; then
            if lsof -i :"$PORT" -sTCP:LISTEN -t 2> /dev/null | grep -q "^$server_pid$"; then
                port_bound=1
                break
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tuln | grep -qE "($HOST|0.0.0.0|\[::\]):$PORT\s"; then
                port_bound=1
                break
            fi
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ "$port_bound" -eq 0 ]; then
        log_message "ERROR" "PHP server process (PID: $server_pid) failed to bind to port $PORT. Check logs: $LOGFILE"
        kill "$server_pid" 2> /dev/null
        manage_pidfile cleanup
        return 1
    fi

    # Log success
    log_message "SUCCESS" "PHP server started successfully with PID: $server_pid"

    # Server started successfully
    return 0
}

# Function: stops the PHP server
stop_server() {
    # Initialize variables
    local server_pid host port
    local found_server=0

    # Attempt to retrieve server info from PID file
    if manage_pidfile check; then
        server_pid=$(manage_pidfile get_value "PID")
        host=$(manage_pidfile get_value "HOST")
        port=$(manage_pidfile get_value "PORT")
        found_server=1
    else
        # Fallback to checking port directly
        host="$HOST"
        port="$PORT"
        local port_pids
        port_pids=$(find_port_processes "$port")
        if [ -n "$port_pids" ]; then
            server_pid="$port_pids"
            found_server=1
        fi
    fi

    # Handle case where no server is found
    if [ "$found_server" -eq 0 ]; then
        log_message "INFO" "No running PHP server found"
        manage_pidfile cleanup
        return 0
    fi

    # Stop the server process
    local failed=0
    if ! kill -0 "$server_pid" 2> /dev/null; then
        log_message "WARNING" "Process $server_pid not found or already terminated"
    else
        log_message "INFO" "Stopping process $server_pid on $host:$port"

        # Attempt SIGTERM with retries
        local attempt=0 max_attempts=3
        while [ "$attempt" -lt "$max_attempts" ] && kill -0 "$server_pid" 2> /dev/null; do
            kill "$server_pid" 2> /dev/null || log_message "WARNING" "Failed to send SIGTERM to $server_pid"
            sleep 1
            attempt=$((attempt + 1))
        done

        # Use SIGKILL if necessary
        if kill -0 "$server_pid" 2> /dev/null; then
            log_message "WARNING" "Process $server_pid did not terminate. Sending SIGKILL..."
            kill -9 "$server_pid" 2> /dev/null
            sleep 1
            if kill -0 "$server_pid" 2> /dev/null; then
                log_message "ERROR" "Failed to terminate process $server_pid"
                failed=1
            fi
        fi
    fi

    # Verify port is free
    if command -v lsof > /dev/null 2>&1 && lsof -i :"$port" -sTCP:LISTEN > /dev/null 2>&1; then
        log_message "ERROR" "Port $host:$port is still in use"
        failed=1
    fi

    # Clean up PID file
    manage_pidfile cleanup

    # Report result
    if [ "$failed" -eq 0 ]; then
        log_message "SUCCESS" "PHP server stopped successfully"
        return 0
    else
        log_message "ERROR" "Failed to stop PHP server completely"
        return 1
    fi
}

# Function: checks the status of the PHP server
check_status() {
    # Check if server is running
    if ! manage_pidfile check; then
        log_message "INFO" "No server running"
        return 1
    fi

    # Retrieve server information
    local server_pid host port docroot router profile
    server_pid=$(manage_pidfile get_value "PID")
    host=$(manage_pidfile get_value "HOST")
    port=$(manage_pidfile get_value "PORT")
    docroot=$(manage_pidfile get_value "DOC_ROOT")
    router=$(manage_pidfile get_value "ROUTER")
    profile=$(manage_pidfile get_value "PROFILE")

    # Display server status
    log_message "INFO" "PHP server is running"
    printf "Server Status:\n"
    printf "  %-15s %s\n" "Status:" "Running"
    printf "  %-15s %s\n" "Profile:" "${profile:-default}"
    printf "  %-15s %s\n" "PID:" "$server_pid"
    printf "  %-15s %s\n" "URL:" "http://$host:$port/"
    printf "  %-15s %s\n" "Document Root:" "$docroot"
    printf "  %-15s %s\n" "Router:" "${router:-None}"
    printf "  %-15s %s\n" "Log file:" "$LOGFILE"

    # Show process start time if available
    if command -v ps > /dev/null 2>&1; then
        local start_time
        start_time=$(ps -o lstart= -p "$server_pid" 2> /dev/null)
        [ -n "$start_time" ] && printf "  %-15s %s\n" "Started:" "$start_time"
    fi

    # Server is running
    return 0
}

# Function: restarts the PHP server
# Function: restarts the PHP server
restart_server() {
    # Log restart operation
    log_message "INFO" "Restarting PHP server..."
    
    # Save current server configuration from PID file before stopping
    local saved_host saved_port saved_docroot saved_router saved_profile
    local config_restored=false
    
    if manage_pidfile check; then
        saved_host=$(manage_pidfile get_value "HOST")
        saved_port=$(manage_pidfile get_value "PORT")
        saved_docroot=$(manage_pidfile get_value "DOC_ROOT")
        saved_router=$(manage_pidfile get_value "ROUTER")
        saved_profile=$(manage_pidfile get_value "PROFILE")
        
        # Update current configuration with saved values
        [[ -n "$saved_host" ]] && HOST="$saved_host"
        [[ -n "$saved_port" ]] && PORT="$saved_port"
        [[ -n "$saved_docroot" ]] && DOC_ROOT="$saved_docroot"
        [[ -n "$saved_router" ]] && ROUTER="$saved_router"
        [[ -n "$saved_profile" ]] && PROFILE="$saved_profile"
        
        config_restored=true
        
        # Log restored configuration details
        log_message "INFO" "Restoring previous configuration:"
        log_message "INFO" "  Document root: $DOC_ROOT"
        [[ -n "$ROUTER" ]] && log_message "INFO" "  Router script: $ROUTER"
        [[ "$PROFILE" != "default" ]] && log_message "INFO" "  Profile: $PROFILE"
        
        log_message "DEBUG" "Full restored config - Host: $HOST, Port: $PORT, DocRoot: $DOC_ROOT, Router: $ROUTER, Profile: $PROFILE"
    else
        log_message "WARNING" "No previous server configuration found, using current settings"
    fi
    
    # Stop existing server
    stop_server
    
    # Wait until port is free (up to 5 seconds)
    local attempt=0 max_attempts=5
    while [ "$attempt" -lt "$max_attempts" ]; do
        if check_port_available "$HOST" "$PORT"; then
            break
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    if [ "$attempt" -eq "$max_attempts" ]; then
        log_message "ERROR" "Port $HOST:$PORT still in use after waiting. Cannot restart server."
        return 1
    fi
    
    # Start new server with restored configuration
    start_server || return 1
    
    # Log success
    log_message "SUCCESS" "PHP server restarted successfully"
    
    # Server restarted successfully
    return 0
}

# Function: sanitizes input for run_wizard (internal helper)
_wizard_sanitize_input() {
    local input="$1"
    # Remove newlines and escape quotes
    echo "$input" | tr -d '\n' | sed 's/"/\\"/g'
}

# Function: runs interactive setup wizard
run_wizard() {
    # Initialize wizard
    log_message "INFO" "Starting configuration wizard..."
    echo "=== PHPMate Configuration Wizard ==="

    # Prompt for hostname
    echo "Enter hostname (default: $HOST):"
    read -r input_host
    if [ -n "$input_host" ]; then
        input_host=$(_wizard_sanitize_input "$input_host")
        if ! validate_hostname "$input_host"; then
            log_message "ERROR" "Invalid hostname"
            return 1
        fi
        HOST="$input_host"
    fi

    # Prompt for port
    echo "Enter port (default: $PORT):"
    read -r input_port
    if [ -n "$input_port" ]; then
        input_port=$(_wizard_sanitize_input "$input_port")
        if ! validate_port "$input_port"; then
            return 1
        fi
        PORT="$input_port"
    fi

    # Prompt for document root
    echo "Enter document root (default: $DOC_ROOT):"
    read -r input_doc_root
    if [ -n "$input_doc_root" ]; then
        input_doc_root=$(_wizard_sanitize_input "$input_doc_root")
        if ! validate_path "$input_doc_root" "dir" "Document root"; then
            return 1
        fi
        DOC_ROOT="$input_doc_root"
    fi

    # Prompt for PHP binary
    echo "Enter PHP binary path (default: $PHP_BIN):"
    read -r input_php_bin
    if [ -n "$input_php_bin" ]; then
        input_php_bin=$(_wizard_sanitize_input "$input_php_bin")
        PHP_BIN="$input_php_bin"
    fi

    # Validate PHP installation
    validate_php || return 1

    # Prompt for router script
    echo "Enter router script path (optional):"
    read -r input_router
    if [ -n "$input_router" ]; then
        input_router=$(_wizard_sanitize_input "$input_router")
        if ! validate_path "$input_router" "file" "Router script"; then
            return 1
        fi
        ROUTER="$input_router"
    else
        ROUTER=""
    fi

    # Prompt for PHP ini file
    echo "Enter custom PHP ini file path (optional):"
    read -r input_php_ini
    if [ -n "$input_php_ini" ]; then
        input_php_ini=$(_wizard_sanitize_input "$input_php_ini")
        if ! validate_path "$input_php_ini" "file" "PHP ini file"; then
            return 1
        fi
        PHP_INI="$input_php_ini"
    else
        PHP_INI=""
    fi

    # Save configuration if desired
    echo "Save this configuration? (Y/n):"
    read -r save_choice
    save_choice=$(_wizard_sanitize_input "${save_choice:-Y}")
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        save_config || return 1
        log_message "SUCCESS" "Configuration saved to $CONFIG_FILE"
    fi

    # Display configuration
    show_config

    # Start server if desired
    echo "Start server with this configuration? (Y/n):"
    read -r start_choice
    start_choice=$(_wizard_sanitize_input "${start_choice:-Y}")
    if [[ "$start_choice" =~ ^[Yy]$ ]]; then
        start_server || return 1
    fi

    # Wizard completed successfully
    return 0
}

# --- Main Script Execution ---

# Function: main entry point
main() {
    # Extract command and shift arguments
    local command=${1:-}
    [ -n "$command" ] && shift

    # Load default configuration
    load_config || return $?

    # Process command-line options
    parse_options "$@" || return $?

    # Execute specified command
    case "$command" in
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        restart)
            restart_server
            ;;
        status)
            check_status
            ;;
        config)
            show_config
            ;;
        wizard)
            run_wizard
            ;;
        version)
            show_version
            ;;
        help | --help | -h)
            usage
            ;;
        "")
            usage
            return 1
            ;;
        *)
            log_message "ERROR" "Unknown command: $command"
            usage
            return 1
            ;;
    esac

    # Return command execution status
    return $?
}
# Execute main function with all arguments
main "$@"
exit $?
