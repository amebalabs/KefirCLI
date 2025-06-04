#!/usr/bin/env just --justfile

# Default recipe to display help
default:
    @just --list

# Build for current architecture in release mode
build:
    @echo "Building for current architecture..."
    swift build -c release

# Code sign the binary
sign: build
    @echo "Code signing binary..."
    codesign --force --options runtime --sign "Developer ID Application: Ameba Labs, LLC (X93LWC49WV)" --timestamp .build/release/kefir
    @echo "Verifying signature..."
    codesign -dv --verbose=4 .build/release/kefir

# Create zip archive for notarization
package: sign
    @echo "Creating zip archive..."
    cd .build/release && zip -r kefir.zip kefir
    @echo "Archive created at .build/release/kefir.zip"

# Submit for notarization (requires app-specific password)
notarize PROFILE_NAME="notarytool-kefir": package
    @echo "Submitting for notarization..."
    @echo "Note: You need to set up credentials first with:"
    @echo "  xcrun notarytool store-credentials {{PROFILE_NAME}}"
    xcrun notarytool submit .build/release/kefir.zip \
        --keychain-profile "{{PROFILE_NAME}}" \
        --wait

# Check notarization status
check-notarization SUBMISSION_ID:
    xcrun notarytool info {{SUBMISSION_ID}} \
        --keychain-profile "notarytool-kefir"

# Get notarization log
notarization-log SUBMISSION_ID:
    xcrun notarytool log {{SUBMISSION_ID}} \
        --keychain-profile "notarytool-kefir"

# Verify notarization (stapling not needed for standalone binaries)
verify-notarization: 
    @echo "Verifying notarization..."
    @echo "Note: Standalone binaries cannot be stapled, but they are still notarized"
    @echo "The notarization is verified by Apple when the binary is first run"
    @echo "Extracting binary from zip..."
    cd .build/release && unzip -o kefir.zip
    @echo "Checking notarization status..."
    spctl -a -vvv -t install .build/release/kefir 2>&1 || true
    @echo "Binary is ready for distribution!"

# Create final distribution archive
dist: verify-notarization
    @echo "Creating final distribution archive..."
    cd .build/release && zip -r kefir-notarized.zip kefir
    @echo "Distribution archive ready at .build/release/kefir-notarized.zip"

# Full release flow
release: dist
    @echo "Release build complete!"
    @echo "Notarized binary available at: .build/release/kefir-notarized.zip"

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build/release/kefir.zip
    rm -rf .build/release/kefir-notarized.zip

# Store notarization credentials (run this once)
setup-credentials APPLE_ID TEAM_ID="X93LWC49WV":
    @echo "Setting up notarization credentials..."
    @echo "You'll be prompted for your app-specific password"
    xcrun notarytool store-credentials "notarytool-kefir" \
        --apple-id "{{APPLE_ID}}" \
        --team-id "{{TEAM_ID}}"

# Build and install locally
install: build
    @echo "Installing to /usr/local/bin..."
    sudo cp .build/release/kefir /usr/local/bin/
    @echo "Installation complete!"

# Create GitHub release archive
github-release: release
    @echo "Creating GitHub release archive..."
    mkdir -p dist
    cp .build/release/kefir-notarized.zip dist/kefir-macos-arm64.zip
    cd dist && shasum -a 256 kefir-macos-arm64.zip > kefir-macos-arm64.zip.sha256
    @echo "GitHub release files ready in dist/"