# Changelog

All notable changes to KefirCLI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2025-06-06

### Fixed
- Configuration file compatibility with Kefir macOS app
- Date encoding/decoding to use ISO8601 format
- Configuration struct naming to match Kefir's format

### Changed
- Aligned configuration format with Kefir macOS app
- Made theme properties immutable to match Kefir
- Removed unused `lastUsedSpeakerId` field

## [1.1.0] - 2025-06-04

### Added
- **Real-time Interactive Mode Updates** 🔄
  - Live polling for instant volume, track, and source changes
  - Song position tracking with progress bars
  - Automatic updates without manual refresh
  - Event-based UI updates for zero-latency feedback
- **Enhanced UI** 🎨
  - Smaller, more refined progress bars
  - Fixed text wrapping for long song titles
  - Improved table formatting (80 char width)
  - Removed noisy update status indicators
  - Better help screen and source menu display
- **Improved Performance** ⚡
  - Smart UI updates to reduce flickering
  - Optimized polling with 10-second intervals
  - Better error recovery in interactive mode

### Changed
- Updated to SwiftKEF 1.1.0 for polling support
- Interactive mode now uses real-time event streaming
- Removed manual 5-second refresh timer
- Changed from local SwiftKEF dependency to published package

### Fixed
- Help screen (h) now displays correctly in interactive mode
- Refresh command (r) now works properly
- UI no longer flickers during updates
- Source menu no longer gets overwritten
- Progress bars no longer duplicate

## [1.0.0] - 2024-XX-XX

### Added
- Initial release
- Speaker profile management
- Interactive TUI mode
- Full speaker control (power, volume, source, playback)
- Configuration file support
- Rich terminal UI with colors and progress bars
- Default speaker support