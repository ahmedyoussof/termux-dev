# Termux Ubuntu Development Environment

A small 3-script setup for a rooted-like Ubuntu development environment on Android without rooting Android.

## Architecture

```text
Android
└── Termux
    ├── Termux:X11
    │   └── XFCE
    │       ├── Terminal
    │       ├── Browser
    │       └── VS Code UI (code-server)
    │
    └── Ubuntu via proot-distro
        ├── root
        ├── developer + sudo
        ├── Git
        ├── Java
        ├── Maven
        ├── Node.js
        ├── Python
        └── Projects
```

The Android device does **not** need to be rooted.

`root` and `sudo` are real Ubuntu users/tools inside the PRoot environment, not Android root.

## Important

The code editor uses **code-server**, which provides the VS Code interface in the XFCE browser while the editor, terminal, Git, Java, Maven, etc. run inside Ubuntu.

From the VS Code integrated terminal:

```bash
sudo -i
```

opens an Ubuntu root shell.

Do not run the editor itself as root unless there is a specific reason.

## Requirements

- Termux
- Termux:X11 Android app
- Working XFCE + Termux:X11 setup
- Internet connection

This project assumes your existing XFCE setup already works.

## First installation

From Termux:

```bash
chmod +x *.sh
./install.sh
```

The installer is idempotent. Running it again verifies the existing installation.

To repair/update the Ubuntu development environment:

```bash
./install.sh repair
```

## Daily startup

Open the Termux:X11 Android application, then from Termux:

```bash
./start.sh
```

The script starts:

1. Termux:X11
2. Existing Termux XFCE
3. Ubuntu-side code-server
4. The VS Code UI in your XFCE browser

Open:

```text
http://127.0.0.1:8080
```

in a browser inside XFCE.

## Stop

```bash
./stop.sh
```

This stops the Ubuntu code-server and XFCE/X11 processes started by the environment.

## Clean

```bash
./stop.sh clean
```

This removes temporary session data and code-server runtime state, but does not remove Ubuntu or your projects.

## Ubuntu access

From any Termux shell:

```bash
./start.sh
```

Then enter Ubuntu manually when needed:

```bash
proot-distro login ubuntu --shared-tmp
```

Inside Ubuntu:

```bash
su - developer
```

or:

```bash
sudo -i
```

## Development paths

Inside Ubuntu:

```text
/home/developer/projects/
├── java/
├── spring/
├── ai/
└── experiments/
```

## Notes

PRoot root is not Android/kernel root. It provides root privileges inside the Ubuntu userland.

PRoot also does not provide normal kernel-level privileges, so software that requires real kernel/container privileges, such as a normal Docker daemon, may not work as it would on a real Linux host.

For Java/Spring development this setup is suitable.
