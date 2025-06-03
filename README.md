# KefirCLI 🎵

A rich, full-featured command-line interface for controlling KEF wireless speakers with an interactive TUI mode and speaker profile management.

> **Note**: This project uses [SwiftKEF](../SwiftKEF) library for speaker communication.

## Features

### 🎯 Core Features
- **Speaker Profiles**: Save and manage multiple speaker configurations
- **Interactive Mode**: Real-time control with keyboard shortcuts and live status updates
- **Rich CLI UI**: Color-coded output, progress bars, and formatted tables
- **Smart Defaults**: Automatically use your default speaker without specifying IP
- **Configuration Management**: Settings saved to `~/.config/kefir/`

### 🎮 Control Capabilities
- **Power Management**: Turn speakers on/off
- **Volume Control**: Set levels, mute/unmute with visual progress bars
- **Source Selection**: Switch between WiFi, Bluetooth, Optical, etc.
- **Playback Control**: Play/pause, skip tracks, view now playing info
- **Status Dashboard**: View comprehensive speaker status at a glance

## Installation

### Build from Source

```bash
cd KefirCLI
swift build -c release
sudo cp .build/release/kefir /usr/local/bin/
```

## Quick Start

### 1. Add Your First Speaker

```bash
# Add a speaker profile
kefir speaker add "Living Room" 192.168.1.100 --default

# List configured speakers
kefir speaker list
```

### 2. Control Your Speaker

```bash
# Use default speaker (no IP needed!)
kefir volume set 50
kefir source set bluetooth
kefir play pause

# Or specify a speaker by name
kefir volume set 30 "Bedroom"

# Or use IP directly for one-off commands
kefir power on 192.168.1.101
```

### 3. Interactive Mode

```bash
# Enter interactive control mode
kefir interactive

# Or for a specific speaker
kefir interactive "Living Room"
```

## Interactive Mode

The interactive mode provides a real-time control interface:

```
🎵 KefirCLI - Living Room
────────────────────────────────────────────────────────────

┌─────────────── Status ───────────────┐
│ Power: ON                            │
│ Source: Bluetooth                    │
│ Volume:                              │
│ [████████████████░░░░░░░░░░░░] 65%  │
│                                      │
│ Now Playing:                         │
│   Title: Wonderful Tonight           │
│   Artist: Eric Clapton               │
│   Album: Slowhand                    │
└──────────────────────────────────────┘

┌───────────── Controls ─────────────┐
│ Volume:     ↑/↓ (adjust)    m (mute/unmute)      │
│ Playback:   SPACE (play/pause)    →/← (next/prev)│
│ Source:     s (change source)                     │
│ Power:      p (toggle power)                      │
│ Display:    r (refresh)    h (help)    q (quit)   │
└───────────────────────────────────────────────────┘
```

### Keyboard Shortcuts

- **↑/↓** or **+/-**: Adjust volume
- **m**: Toggle mute
- **SPACE**: Play/pause
- **→/←**: Next/previous track
- **s**: Change input source
- **p**: Toggle power
- **r**: Refresh status
- **h** or **?**: Show help
- **q** or **Ctrl+C**: Quit

## Command Reference

### Speaker Management

```bash
# Add a new speaker
kefir speaker add <name> <host> [--default]

# List all speakers
kefir speaker list

# Remove a speaker
kefir speaker remove <name>

# Set default speaker
kefir speaker set-default <name>
```

### Volume Control

```bash
# Set volume (0-100)
kefir volume set <level> [speaker]

# Get current volume
kefir volume get [speaker]

# Mute/unmute
kefir volume mute [speaker]
kefir volume unmute [speaker]
```

### Power Control

```bash
# Power on/off
kefir power on [speaker]
kefir power off [speaker]
```

### Source Control

```bash
# Set input source
kefir source set <source> [speaker]

# Get current source
kefir source get [speaker]

# List available sources
kefir source list
```

Available sources: wifi, bluetooth, tv, optic, coaxial, analog, usb

### Playback Control

```bash
# Play/pause toggle
kefir play pause [speaker]

# Skip tracks
kefir play next [speaker]
kefir play previous [speaker]

# Get track info
kefir play info [speaker]
```

### Information & Status

```bash
# Get speaker information
kefir info [speaker]

# Get current status (default command)
kefir status [speaker]
kefir [speaker]  # Same as status
```

### Configuration

```bash
# Configure theme
kefir config theme --enable-colors --enable-emojis
kefir config theme --disable-colors --disable-emojis

# Show config location
kefir config show
```

## Configuration

KefirCLI stores its configuration in `~/.config/kefir/config.json`:

```json
{
  "speakers": [
    {
      "id": "UUID",
      "name": "Living Room",
      "host": "192.168.1.100",
      "isDefault": true,
      "lastSeen": "2024-01-15T10:30:00Z"
    }
  ],
  "theme": {
    "useColors": true,
    "useEmojis": true
  }
}
```

## Examples

### Morning Routine Script

```bash
#!/bin/bash
# morning-music.sh

# Turn on living room speakers
kefir power on "Living Room"

# Set comfortable morning volume
kefir volume set 25 "Living Room"

# Switch to Bluetooth for phone
kefir source set bluetooth "Living Room"
```

### Quick Status Check

```bash
# Check all speakers
for speaker in $(kefir speaker list | grep -E '^\s+\w+' | awk '{print $1}'); do
    echo "=== $speaker ==="
    kefir status "$speaker"
done
```

## Requirements

- macOS 10.15+
- Swift 6.1+
- KEF wireless speaker on the same network

## Supported Speakers

- KEF LSX II
- KEF LS50 Wireless II
- KEF LS60

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run kefir speaker list
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests.

## License

MIT License - see LICENSE file for details.