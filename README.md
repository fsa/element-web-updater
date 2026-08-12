# Element Web Updater

A simple Bash script for installing and updating [Element Web](https://github.com/element-hq/element-web) from GitHub releases.

> [!WARNING]
> **Back up your `config.json` before using this script.**
>
> The script is designed to preserve `config.json` during updates, but you should always keep a separate backup copy in a safe location. Use this script at your own risk.

## Features

- Automatically detects the latest Element Web release.
- Checks the currently installed version and skips the update if it is already up to date.
- Supports both fresh installations and updates.
- Preserves the existing `config.json`.
- Downloads and verifies the release archive (SHA-256) before touching the current installation.
- Removes files from previous releases that are no longer present in the new release.
- Shows a download progress bar when run interactively and stays quiet under `systemd`, cron, or another non-interactive environment.

## Requirements

- Bash
- `curl`
- `sha256sum`
- `tar`
- `find`
- `sed` and `awk` (POSIX, normally preinstalled)

No additional packages or runtime environments are required.

## Configuration

The script is configured using variables at the very top of the script. All of them can also be overridden using an optional `.env` file.

### `DESTINATION`

The directory where Element Web is installed.

Default:

```bash
DESTINATION="$HOME/public_html"
```

Example:

```dotenv
DESTINATION="/var/www/element"
```

### `TMP_DIR`

The directory used for downloading the release archive and temporarily extracting it before installation.

It **must be different from `DESTINATION`**.

Default:

```bash
TMP_DIR="/tmp"
```

Example:

```dotenv
TMP_DIR="/var/tmp/element"
```

### `REPO`

The GitHub repository from which the Element Web releases are downloaded.

Default:

```bash
REPO="element-hq/element-web"
```

Example:

```dotenv
REPO="element-hq/element-web"
```

### `.env`

The `.env` file is optional. If present in the current working directory, it overrides the default values.

Only the `DESTINATION`, `TMP_DIR` and `REPO` keys are read; everything else is ignored. Values may be quoted, comments and empty lines are allowed. The file is parsed, not executed.

Example:

```dotenv
DESTINATION="/var/www/element"
TMP_DIR="/var/tmp/element"
REPO="element-hq/element-web"
```

If no `.env` file is provided, the default values defined in the script are used.

Because the file is looked up in the current working directory, when running the script from `cron` or a `systemd` timer make sure the working directory (the `WorkingDirectory=` option in systemd, or a `cd` in cron) points to the directory that contains `.env`.

## How it works

The installed version is read from `$DESTINATION/version`. This file is shipped inside the release archive itself (its value includes a `v` prefix, e.g. `v1.12.25`, which the script normalizes), so the script does not maintain its own version file.

For a fresh install, `$DESTINATION` must be empty except for `config.json`. This prevents the script from accidentally overwriting unrelated files.

For an existing installation, the script:

1. Checks the latest Element Web release on GitHub.
2. Downloads the release archive to `$TMP_DIR` and verifies its SHA-256 digest.
3. Extracts the archive to a temporary directory.
4. Verifies the archive looks like Element Web (contains `index.html` and `version`).
5. Removes the old installation files (keeping `config.json`) and copies the new release into place.
6. The `version` file is copied together with the other files, so the installed version is always tracked.

If downloading, verifying or extracting fails, the current installation is left untouched.

Note: step 5 is **not atomic** — the old files are deleted before the new ones are copied. A failure during the copy (for example a full disk) can leave a partial installation. Keep a backup.

## Usage

Make the script executable and run it:

```bash
chmod +x element-web-updater.sh
./element-web-updater.sh
```

or run it directly with Bash:

```bash
bash element-web-updater.sh
```

Files are copied with the permissions and ownership of the user running the script. If your web server runs under a different user (for example `www-data`), make sure the installation directory is writable by the script's user, or run the script as the web server user and adjust ownership afterwards.

The script can also be executed periodically using `systemd` timers or another scheduler.

## Configuration file

The `config.json` file is considered user-managed and is never overwritten by the script.

The release archive ships a `config.sample.json` instead of a `config.json`. As a safety measure the script also removes any `config.json` from the extracted archive before copying, so a preserved user configuration always survives an update.

## Important

The script preserves the existing `config.json` during installation and updates. However, you should **always keep a backup copy of your `config.json` in a safe location** before using the script.

The author is not responsible for any data loss, configuration loss, service interruption, or other damage resulting from the use of this script.

Use the script at your own risk and make sure you have a working backup before performing an update.
