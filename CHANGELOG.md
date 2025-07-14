# Changelog

All notable changes to Phmate will be documented in this file.

## [1.1.0] - 2025-07-13

### Added
- Auto-detection of `router.php` file in document root directory
- Automatic router script usage when no explicit `--router` option is provided
- Enhanced logging to indicate whether explicit or auto-detected router is being used
- Improved PID file management to track auto-detected router scripts

## [1.0.1] - 13/07/2025

### Fixed
- Fixed issue where `restart` command would not remember custom `--docroot` and `--router` options
- Server restart now preserves all original startup parameters (document root, router script, profile, etc

## [1.0.0] - 25/03/2025

### Added
- Initial private release with full management.

### Changed
- N/A

### Fixed
- N/A

## [0.1.0] - 19/03/2025

### Added
- Initial project structure
- Basic management functionality (start, stop, status)

### Changed
- N/A (initial release)

### Fixed
- N/A (initial release)