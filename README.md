# Termux Ubuntu Development Environment

A lightweight Linux development workstation on Android using:

- Termux
- Termux:X11
- XFCE
- Ubuntu via `proot-distro`
- Ubuntu `developer` user + `sudo`
- Java 17
- Maven
- Node.js
- Python
- Git
- code-server (VS Code interface)

## Architecture

```text
Android
└── Termux
    ├── Git                  # bootstrap prerequisite
    ├── Termux:X11           # display server
    └── Ubuntu (PRoot)
        ├── root
        ├── developer + sudo
        ├── Git
        ├── Java
        ├── Maven
        ├── Node.js
        ├── Python
        ├── code-server
        └── /home/developer/projects

Termux:X11
└── XFCE
    ├── Terminal
    ├── Browser
    └── VS Code (code-server)
```

**XFCE is the desktop you see in the Termux:X11 Android app.**

Ubuntu is the development environment underneath it. GUI applications running inside Ubuntu can use the Termux:X11 display.

Android does **not** need to be rooted. Ubuntu `root` is PRoot root, not Android/kernel root.

---

# Android Preparation

Do these steps once before installing the environment.

## 1. Use compatible Termux packages

Install Termux and Termux:X11 from compatible releases in the same ecosystem. Avoid mixing Termux packages from different sources.

You need:

```text
Termux
Termux:X11
```

Termux:X11 project:

https://github.com/termux/termux-x11

## 2. Enable storage access

In Termux:

```bash
termux-setup-storage
```

Accept the Android permission.

This creates:

```text
~/storage/
├── shared
├── downloads
├── dcim
└── ...
```

Use shared storage mainly for moving files between Android and Linux.

Keep your development projects inside Ubuntu:

```text
/home/developer/projects
```

Do **not** put Maven/Node projects on `/storage/emulated/0` unless you have a specific reason. Android shared storage can be slower and has different filesystem permissions.

## 3. Disable battery optimization

This is important.

For **Termux**:

```text
Android Settings
→ Apps
→ Termux
→ Battery
→ Unrestricted / No restrictions
```

Do the same for:

```text
Termux:X11
```

Also allow background activity if your Android version/device provides that option.

Some manufacturers have additional settings such as:

```text
Auto-start
Background activity
Background launch
Battery optimization
```

Allow Termux and Termux:X11 to keep running.

## 4. Storage

Keep enough free storage for:

```text
Ubuntu
Java
Maven
Node.js
Python
code-server
Maven ~/.m2
npm cache
projects
build artifacts
```

For serious development, having roughly **10–20 GB or more free** is recommended.

## 5. Optional wake lock

For long builds or long-running development sessions:

```bash
termux-wake-lock
```

Release it when finished:

```bash
termux-wake-unlock
```

This can increase battery usage, so use it only when needed.

## 6. Network/security

code-server is configured for:

```text
127.0.0.1:8080
```

This keeps it accessible only from the Android device.

Do not change it to `0.0.0.0` unless you intentionally want to expose the editor to another device.

## 7. Android root is not required

You do not need:

```text
Magisk
Android root
Bootloader changes
ADB
Developer Options
```

for the normal setup.

---

# First Installation

Native Termux Git is a bootstrap prerequisite.

Run:

```bash
pkg update
pkg upgrade -y
pkg install git -y
```

Clone the repository:

```bash
git clone <YOUR_REPOSITORY_URL> ~/termux-dev
cd ~/termux-dev
chmod +x *.sh
```

Install:

```bash
./install.sh
```

The installer is idempotent. Running it again verifies existing components and skips what is already installed. Ubuntu packages are checked with `dpkg-query` first, so `apt-get update` only runs when something is genuinely missing.

Re-apply all configuration fixes **without downloading anything**:

```bash
./install.sh repair
```

Repair and also install anything that is actually missing:

```bash
./install.sh repair --full
```

Verify only:

```bash
./install.sh verify
```

The installer does **not** run `pkg upgrade` automatically.

---

# Start

Open the **Termux:X11 Android application**, then in Termux:

```bash
cd ~/termux-dev
./start.sh
```

The startup sequence is:

```text
Termux:X11
    ↓
DISPLAY=:0
    ↓
Ubuntu
    ↓
XFCE
    ↓
code-server
```

`start.sh` also tries to open the Termux:X11 activity for you. To use a different display:

```bash
TERMUX_DEV_DISPLAY=:1 ./start.sh
```

You should see XFCE inside Termux:X11.

Open the VS Code interface from the XFCE browser:

```text
http://127.0.0.1:8080
```

Default initial code-server password:

```text
termux-dev
```

Change it after the first login.

---

# Ubuntu Access

From **Termux** (the XFCE terminal is already inside Ubuntu):

```bash
ubuntu
```

The alias is added to `~/.bashrc` by the installer and is available in new Termux sessions. The full form is:

```bash
proot-distro login ubuntu --user developer --shared-tmp
```

Check:

```bash
whoami
```

Expected:

```text
developer
```

Get Ubuntu root:

```bash
sudo -i
```

or:

```bash
sudo command
```

This is root inside Ubuntu/PRoot, not Android root.

---

# Development

Development tools are installed inside Ubuntu:

```text
Git
Java 17
Maven
Node.js
Python
code-server
```

Projects:

```text
/home/developer/projects
```

Example:

```bash
cd ~/projects
git clone <project>
cd <project>
./mvnw spring-boot:run
```

---

# Stop

Normal stop:

```bash
./stop.sh
```

Stop and clean runtime state:

```bash
./stop.sh clean
```

---

# Useful Commands

```bash
./install.sh                # Install / verify
./install.sh repair         # Re-apply config fixes (no downloads)
./install.sh repair --full  # Repair + install anything missing
./install.sh verify         # Verify only
./start.sh                  # Start X11 + Ubuntu + XFCE + code-server
./stop.sh                   # Stop
./stop.sh clean             # Stop + clean runtime data
```

---

# Updating Termux

The project intentionally does not run a full Termux upgrade automatically.

When you want to update the native Termux environment:

```bash
pkg update
pkg upgrade
```

Then restart the development environment.

Ubuntu packages can be updated from Ubuntu:

```bash
sudo apt update
sudo apt upgrade
```

---

# Troubleshooting

All logs live in one place:

```text
~/.termux-dev/logs/termux-x11.log
~/.termux-dev/logs/xfce.log
~/.termux-dev/logs/code-server.log
```

## Black screen in Termux:X11

First:

```bash
./stop.sh clean
./install.sh repair
./start.sh
```

`repair` re-applies the anti-black-screen configuration and downloads nothing:

- `xfwm4` compositing disabled (software GL renders a black surface under Termux:X11)
- DPMS/screen blanking disabled (`xset s off -dpms`)
- `xfce4-screensaver`, `light-locker` and `xscreensaver` autostart disabled

Then make sure the Termux:X11 Android application is actually in the foreground, and check `termux-x11.log`.

## XFCE does not start

Run:

```bash
./stop.sh clean
./install.sh repair
./start.sh
```

Then inspect `xfce.log`. Common causes, all handled by `repair`:

- missing `/etc/machine-id`, which makes D-Bus refuse to start a session bus
- the X socket not being visible inside Ubuntu (requires `--shared-tmp`)
- the session being backgrounded inside PRoot, which kills it immediately

Services are deliberately run in the **foreground inside PRoot** and backgrounded from Termux. PRoot traces every process in the container, so a session backgrounded inside a `proot-distro login` that then exits is torn down with it.

## Android keeps killing the desktop

Check:

```text
Termux → Battery → Unrestricted
Termux:X11 → Battery → Unrestricted
```

Also check your device manufacturer's background/auto-start settings.

## code-server does not open

Restart:

```bash
./stop.sh
./start.sh
```

Then open:

```text
http://127.0.0.1:8080
```

---

# Design Principles

The project intentionally uses only three scripts:

```text
install.sh
start.sh
stop.sh
```

The installation script contains the environment layers, while start/stop remain small for fast daily use.

Native Termux Git is only for bootstrapping the repository.

Ubuntu has its own Git for development.

No Android root is required.
