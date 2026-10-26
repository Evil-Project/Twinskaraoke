#!/bin/sh
# WidgetKit and Shortcuts require a Team ID in the simulator app signature.
# Xcode 27 otherwise signs simulator products ad hoc, which linkd rejects.
set -eu
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then exit 0; fi
if [ "${PLATFORM_NAME:-}" != "iphonesimulator" ]; then exit 0; fi
app_path="${BUILT_PRODUCTS_DIR:?}/Twinskaraoke.app"
widget_path="$app_path/PlugIns/TwinskaraokeWidgets.appex"
if [ ! -d "$app_path" ] || [ ! -d "$widget_path" ]; then exit 0; fi
identity="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | /usr/bin/head -n 1)"
if [ -z "$identity" ]; then
  echo 'No Apple Development signing identity is available for simulator App Intents.' >&2
  exit 1
fi
/usr/bin/codesign --force --sign "$identity" --preserve-metadata=entitlements --generate-entitlement-der "$widget_path"
/usr/bin/codesign --force --sign "$identity" --preserve-metadata=entitlements --generate-entitlement-der "$app_path"
