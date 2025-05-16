#!/bin/bash
# Phmate Installation Script

set -e

# Default installation paths
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
DOCDIR="${DOCDIR:-$PREFIX/share/doc/phmate}"
MANDIR="${MANDIR:-$PREFIX/share/man/man1}"
COMPLETIONDIR="${COMPLETIONDIR:-$PREFIX/share/bash-completion/completions}"

# Check for root permissions
if [ ! -w "$PREFIX" ]; then
    echo "Error: Need root permissions to install to $PREFIX. Please run with sudo."
    exit 1
fi

# Confirm installation
echo "=== Phmate Installation ==="
echo "This will install PHPMate to:"
echo "  Binary:      $BINDIR"
echo "  Docs:        $DOCDIR"
echo "  Man Page:    $MANDIR"
echo "  Completion:  $COMPLETIONDIR"
echo ""
read -r -p "Are you sure you want to install PHPMate? (y/N): " confirm
[[ $confirm =~ ^[Yy]$ ]] || {
    echo "Installation aborted."
    exit 0
}

# Create directories with error checking
echo "Creating directories..."
for dir in "$BINDIR" "$DOCDIR" "$MANDIR" "$COMPLETIONDIR"; do
    mkdir -p "$dir" || {
        echo "Failed to create $dir"
        exit 1
    }
done

# Check PHP version
echo "Checking PHP version..."
php_version=$(php -v 2> /dev/null | grep -oE 'PHP [0-9]+\.[0-9]+\.[0-9]+' | cut -d' ' -f2) || {
    echo "Error: Failed to retrieve PHP version. Ensure PHP is installed."
    exit 1
}
min_version="8.0.0"
if [ "$(printf '%s\n' "$min_version" "$php_version" | sort -V | head -n1)" != "$min_version" ]; then
    echo "Error: PHP version $php_version is too old. Required: $min_version or higher."
    exit 1
fi
echo "PHP version $php_version is compatible."

# Install the script
echo "Installing the script..."
install -m 755 src/phmate.sh "$BINDIR/phmate" || {
    echo "Failed to install phmate.sh"
    exit 1
}

# Install documentation
echo "Installing documentation..."
for doc in README.md CHANGELOG.md LICENSE; do
    if [ -f "$doc" ]; then
        install -m 644 "$doc" "$DOCDIR/" || {
            echo "Failed to install $doc"
            exit 1
        }
    fi
done
if [ -f docs/man/phmate.1 ]; then
    if ! install -m 644 docs/man/phmate.1 "$MANDIR/"; then
        echo "Failed to install man page"
        exit 1
    fi
fi

# Install bash completion
echo "Installing bash completion..."
if [ -f completion/bash/phmate ]; then
    install -m 644 completion/bash/phmate "$COMPLETIONDIR/" || {
        echo "Failed to install bash completion"
        exit 1
    }
fi

echo ""
echo "Installation complete!"
echo "Run 'phmate help' to get started."
