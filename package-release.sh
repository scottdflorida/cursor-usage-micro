#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app_name="Cursor Usage Micro"
artifact_name="cursor-usage-micro"
target_arch=${TARGET_ARCH:-$(uname -m)}

: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to a Developer ID Application identity}"
: "${APPLE_API_KEY_PATH:?Set APPLE_API_KEY_PATH to an App Store Connect API key file}"
: "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?Set APPLE_API_ISSUER_ID}"

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  print -u2 -- "A Developer ID signature is required for a release."
  exit 1
fi

TARGET_ARCH="$target_arch" CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" "$project_dir/build.sh"

app_path="$project_dir/build/$app_name.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
submission_path="$project_dir/build/$artifact_name-$version-$target_arch-notarization.zip"
artifact_path="$project_dir/build/$artifact_name-$version-$target_arch.zip"

codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_path"
xcrun notarytool submit "$submission_path" \
  --key "$APPLE_API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_path"
rm -f "$submission_path"

echo "$artifact_path"
