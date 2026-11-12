#!/bin/sh
# Installs third-party notices into a macOS app bundle.
#
# codesign rejects non-code files under Contents/MacOS, so notices go to
# Contents/Resources and keep the codecs/licenses/<component>/ tree that
# third_party_licenses.dart parses.
#
# Callers use plain globals (no local in POSIX sh), so the names here are
# prefixed to avoid clobbering their variables.
install_notices() {
  notices_bundle=$1
  notices_component=$2
  notices_source=$3
  notices_destination="$notices_bundle/Contents/Resources/codecs/licenses/$notices_component"
  mkdir -p "$notices_destination"
  cp "$notices_source"/* "$notices_destination/"
}
