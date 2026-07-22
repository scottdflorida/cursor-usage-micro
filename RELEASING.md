# Releasing Cursor Usage Micro

Releases are built for Apple silicon and Intel, signed with Developer ID, notarized by Apple, and published only after both packages pass.

## One-time setup

1. Join the Apple Developer Program.
2. Create a `Developer ID Application` certificate and export it with its private key as a password-protected `.p12` file.
3. Create an App Store Connect API key and download its `.p8` file.
4. Add these GitHub Actions secrets to this repository:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64-encoded contents of the exported `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `RELEASE_KEYCHAIN_PASSWORD` | A new random password used only for the temporary CI keychain |
| `APPLE_API_PRIVATE_KEY` | Complete contents of the App Store Connect `.p8` file |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

The workflow writes signing material only to the runner's temporary directory and removes it in an always-run cleanup step.

## Publish a version

1. Update and test `main`.
2. Create an annotated semantic-version tag, such as `v0.2.0`.
3. Push the tag.

The release workflow creates a draft, runs the full tests on both architectures, signs and notarizes each app, uploads both ZIP files, and then publishes the release. If either build fails, the release stays in draft form for inspection.

```sh
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

The tag controls the public version number. GitHub's workflow run number supplies the internal bundle build number.

## Local packaging

`package-release.sh` uses the same environment variables as CI. It refuses to create a public package with an ad hoc signature.
