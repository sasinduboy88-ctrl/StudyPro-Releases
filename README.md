# StudyPro — Official Releases

This public repository is reserved for **signed StudyPro Student Edition releases** and the Tauri updater manifest.

## Download
Use the [Releases page](https://github.com/sasinduboy88-ctrl/StudyPro-Releases/releases) to download an installer. The in-app updater checks the latest release and asks before installing an update.

## Release integrity
- Windows installers must be signed with the StudyPro Tauri updater signing key.
- The updater verifies the signature before installing an update.
- Release assets should include the Windows installer, its signature, and `latest.json`.
- Do not use temporary GitHub Actions build artifacts as official releases.

## Security
Never upload source archives, activation voucher inventories, private signing keys, passwords, or access tokens to this public repository. The private source and release workflow are maintained in [StudyPro](https://github.com/sasinduboy88-ctrl/StudyPro).

A release is official only when it appears on the Releases page with its signed updater manifest.
