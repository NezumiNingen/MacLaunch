# MacLaunch update channel

The app checks releases from `NezumiNingen/MacLaunch` by default. Xcode merges `Config/UpdateChannel.plist` into the generated app metadata, so a downloaded copy uses the same update source on every Mac. To build a copy for another maintained repository, override these settings on the **LaunchNext** Xcode target used internally by this MacLaunch fork:

- `LAUNCHNEXT_UPDATE_REPOSITORY_OWNER`
- `LAUNCHNEXT_UPDATE_REPOSITORY_NAME`

For command-line builds, override the values when needed, for example:

```sh
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release \
  LAUNCHNEXT_UPDATE_REPOSITORY_OWNER=your-account \
  LAUNCHNEXT_UPDATE_REPOSITORY_NAME=your-maclaunch-fork
```

The release scripts default to `NezumiNingen/MacLaunch` and accept the same overrides from the environment:

```sh
LAUNCHNEXT_UPDATE_REPOSITORY_OWNER=your-account \
LAUNCHNEXT_UPDATE_REPOSITORY_NAME=your-maclaunch-fork \
./scripts/release-notarized.sh --notarize
```

Both settings must be valid GitHub path components and must be set together. The app and standalone updater default to this fork's `NezumiNingen/MacLaunch` release feed; the app also passes its configured repository explicitly to the updater.

The repository must be public for the app's unauthenticated GitHub API requests. Publish release ZIP assets named like `MacLaunch2.5.0.zip` so they match the updater's existing asset filter. Keep the release tag compatible with the app's semantic-version comparison.
