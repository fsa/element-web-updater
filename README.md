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

The script can also be executed periodically using `systemd` timers. See [Scheduled updates (systemd timer)](#scheduled-updates-systemd-timer).

## Releases

Release archives are published on the [Releases](https://github.com/fsa/element-web-updater/releases) page and contain:

- `element-web-updater-<version>.tar.gz` — the script, the `README.md` and the `LICENSE` (MIT);
- `SHA256SUMS` — checksums of the archive for integrity verification.

Verify the archive before using it:

```bash
sha256sum -c SHA256SUMS
```

The project is licensed under the [MIT license](LICENSE).

## Scheduled updates (systemd timer)

The updater can be run on a schedule with a systemd timer. The service should run as the user that runs the web server (for example `www-data`), so that the installed files get the correct ownership and permissions.

### Service unit

Create `/etc/systemd/system/element-web-update.service`:

```ini
[Unit]
Description=Update Element Web
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=www-data
Group=www-data
WorkingDirectory=/srv/element-web-updater
ExecStart=/srv/element-web-updater/element-web-updater.sh
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
```

Notes on the service unit:

- `User=` and `Group=` must be set to the user that runs the web server (here `www-data`). That user must be able to read and execute the updater script and to write to `DESTINATION`.
- `WorkingDirectory=` must point to the directory that contains the updater's `.env` file — the script looks it up in the current working directory. If you do not use a `.env` file, point it to any directory and configure `DESTINATION`, `TMP_DIR` and `REPO` at the top of the script instead.
- `PrivateTmp=true` gives the service an isolated temporary directory. With the default `TMP_DIR=/tmp` the download and extraction happen inside that private directory and are cleaned up automatically.
- When run by systemd, stdout is not a terminal, so the script stays quiet and does not show a progress bar.

### Timer unit

Create `/etc/systemd/system/element-web-update.timer`:

```ini
[Unit]
Description=Run the Element Web updater daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
```

- `OnCalendar=daily` runs the update once a day; other schedules are possible, for example `OnCalendar=*-*-* 03:00:00` for a fixed time.
- `RandomizedDelaySec` spreads the run over up to 15 minutes to avoid load spikes.
- `Persistent=true` runs a missed update right after boot if the machine was off at the scheduled time.

### Enabling the timer

Make sure the installation directory is writable by the web server user, and that the updater script and its `.env` file are readable by it:

```bash
sudo chown -R www-data:www-data /var/www/element
```

Then enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now element-web-update.timer
```

Check the schedule and the results of the last run:

```bash
systemctl list-timers element-web-update.timer
systemctl status element-web-update.service
journalctl -u element-web-update.service
```

To trigger an update manually under the same conditions as the timer:

```bash
sudo systemctl start element-web-update.service
```

### Notes

- If `DESTINATION` is not writable by the user set with `User=`, the update will fail. Either run the service as the owner of the installation directory, or change its ownership with `chown`.
- With `ProtectSystem=full`, the directories `/usr`, `/boot` and `/etc` are read-only. `DESTINATION` and `TMP_DIR` must live outside of them; if that does not fit your setup, drop or adjust the hardening options.
- The examples assume the web server runs under `www-data` and that `.env` contains `DESTINATION="/var/www/element"`. Adjust `User=`, `Group=`, `WorkingDirectory=` and the `chown` target to your environment.

## Configuration file

The `config.json` file is considered user-managed and is never overwritten by the script.

The release archive ships a `config.sample.json` instead of a `config.json`. As a safety measure the script also removes any `config.json` from the extracted archive before copying, so a preserved user configuration always survives an update.

## Important

The script preserves the existing `config.json` during installation and updates. However, you should **always keep a backup copy of your `config.json` in a safe location** before using the script.

The author is not responsible for any data loss, configuration loss, service interruption, or other damage resulting from the use of this script.

Use the script at your own risk and make sure you have a working backup before performing an update.
