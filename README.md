# Element Web Updater

A simple Bash script for installing and updating [Element Web](https://github.com/element-hq/element-web) from GitHub releases.

> [!WARNING]
> **Back up your `config.json` before using this script.**
>
> The script is designed to preserve `config.json` during updates, but you should always keep a separate backup copy in a safe location. Use this script at your own risk.

## Features

- Automatically detects the latest Element Web release.
- Checks the currently installed version.
- Skips the update if the latest version is already installed.
- Supports both fresh installations and updates.
- Preserves the existing `config.json`.
- Safely downloads and extracts the new release before replacing the current installation.
- Removes files from previous releases that are no longer present in the new release.
- Shows a download progress bar when run interactively.
- Keeps output clean when run from `systemd`, cron, or another non-interactive environment.

## Requirements

- Bash
- `curl`
- `grep` with PCRE support
- `tar`
- `find`

No additional packages or runtime environments are required.

## Configuration

The script can be configured using variables defined at the beginning of the script. All of these variables can also be overridden using an optional `.env` file.

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

The `.env` file is optional. If present in the current working directory, it is loaded by the script and its values override the default values.

Example:

```dotenv
DESTINATION="/var/www/element"
TMP_DIR="/var/tmp/element"
REPO="element-hq/element-web"
```

If no `.env` file is provided, the default values defined in the script are used.

## How it works

The script checks for the installed version in:

```text
$DESTINATION/version
```

If no version is found, the destination directory must be empty, except for `config.json`. This prevents the script from accidentally overwriting unrelated files.

For an existing installation, the script:

1. Checks the latest Element Web release on GitHub.
2. Downloads the release archive to a temporary directory.
3. Extracts the archive to a temporary directory.
4. Preserves the existing `config.json`.
5. Replaces the installed Element Web files with the new release.
6. Removes files that were present in the previous release but are no longer included.
7. Updates the `version` file.

If downloading or extracting the new release fails, the existing installation is left untouched.

## Usage

Run the script manually:

```bash
./update-element.sh
```

It can also be executed periodically using `systemd` timers or another scheduler.

## Configuration file

The `config.json` file is considered user-managed and is never overwritten by the script.

The configuration shipped with Element Web is ignored during extraction, allowing the local configuration to survive updates.

## Important

The script preserves the existing `config.json` during installation and updates. However, you should **always keep a backup copy of your `config.json` in a safe location** before using the script.

The author is not responsible for any data loss, configuration loss, service interruption, or other damage resulting from the use of this script.

Use the script at your own risk and make sure you have a working backup before performing an update.
