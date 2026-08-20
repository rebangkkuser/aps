
Changelog

All notable changes to APS 2.0 are documented below.

[2.0.0] - Hotfix!🥳

Added

- Added a new package dependency system through "indexOfDeps".
- Added package conflict detection through "indexOfBreaks".
- Added mandatory SHA-256 package verification through "indexOfhashes".
- Added "--dhash" to explicitly bypass SHA-256 verification.
- Added recursive dependency resolution and installation.
- Added circular dependency detection.
- Added "aps search" for searching available packages.
- Added "aps info" for displaying package information.
- Added "aps list" for listing installed APS packages.
- Added "aps clean" for cleaning temporary files.
- Added installation and removal confirmation prompts.
- Added "-y" to skip confirmation prompts.
- Added command aliases:
  - "ins" and "get" for "install"
  - "insy" for "install -y"
  - "rm" and "del" for "remove"
  - "rmy" for "remove -y"
  - "dl" for "download"
- Added automatic terminal color detection.
- Added improved package metadata handling.
- Added improved repository index handling.

Security

- APK downloads are verified against their repository-provided SHA-256 hash before installation.
- Installation is refused when a package does not have a registered SHA-256 hash.
- Installation is refused when the downloaded APK does not match its expected hash.
- SHA-256 verification can only be bypassed explicitly with "--dhash".

Improved

- Improved package discovery and repository synchronization.
- Improved dependency handling.
- Improved conflict detection.
- Improved error messages.
- Improved installation and removal workflows.
- Improved command-line usability.
- Improved validation of package names and Android package IDs.
- Improved handling of optional repository indexes.

Repository

- Added support for separate repository indexes for:
  - Package dependencies
  - Package conflicts
  - Package SHA-256 hashes
- Repository indexes remain simple text files and can be maintained without additional tooling.

Removed

- Removed the "verIndex" system.
- Removed version-channel handling such as alpha, beta, RC, and nightly packages.
- Removed the "upgrade" command from the initial 2.0 release.

Compatibility

- Existing APS repositories can continue to provide the basic "index" and "indexName" files.
- Optional indexes are ignored when unavailable.
- SHA-256 verification is mandatory unless explicitly bypassed with "--dhash".

[2.0.0]

APS 2.0 introduces a more complete package management system while keeping the repository format simple, lightweight, and easy to maintain.
