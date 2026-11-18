# Guide: Affinity by Canva on Linux, signed in

This guide takes you from a Linux system without Affinity to Affinity running under Wine, signed in to Canva, with the AI tools from your Canva plan available.

It was written on Arch-based CachyOS with KDE Plasma, using [Linux-Affinity-Installer](https://github.com/ryzendew/Linux-Affinity-Installer). Commands for other distributions are given where they differ. If something goes wrong at any step, see [Troubleshooting](TROUBLESHOOTING.md).

**Time:** about 30–60 minutes, mostly waiting for downloads and .NET to install.
**Disk space:** about 10 GB.

## Contents

1. [Install the dependencies](#1-install-the-dependencies)
2. [Install Affinity with Linux-Affinity-Installer](#2-install-affinity-with-linux-affinity-installer)
3. [Fix the interface size](#3-fix-the-interface-size)
4. [Install the connector](#4-install-the-connector)
5. [Sign in to Canva](#5-sign-in-to-canva)
6. [Use the AI tools](#6-use-the-ai-tools)
7. [Keeping it working](#7-keeping-it-working)

---

## 1. Install the dependencies

Linux-Affinity-Installer can install its own dependencies, but then it asks for your `sudo` password inside its window. Installing them yourself first keeps the password in your own terminal.

**Arch, CachyOS, EndeavourOS:**

```bash
sudo pacman -Syu --needed wine winetricks wget curl p7zip tar jq zstd unzip \
  dotnet-sdk dotnet-sdk-8.0 dotnet-sdk-10.0 python-pyqt6 xdg-utils xz
```

**Other distributions:** see the installer's [per-distribution list](https://github.com/ryzendew/Linux-Affinity-Installer/tree/main/docs), and add the connector's tools: `curl`, `7z`, `xdg-utils`, `xz` (package names are in the [README](../README.md#what-you-need-first)).

`-Syu` updates the rest of your system first. If it updates the kernel, reboot before continuing.

## 2. Install Affinity with Linux-Affinity-Installer

1. Download the installer script and read it before running it. It's a Python program that downloads Wine, .NET and Affinity:

   ```bash
   mkdir -p ~/.local/share/affinity-installer
   curl -sSL -o ~/.local/share/affinity-installer/AffinityLinuxInstaller.py \
     https://raw.githubusercontent.com/ryzendew/Linux-Affinity-Installer/main/AffinityScripts/AffinityLinuxInstaller.py
   python3 ~/.local/share/affinity-installer/AffinityLinuxInstaller.py
   ```

2. In the installer window, click **One-Click Full Setup**.
3. Keep the defaults:
   - **Install folder:** `~/.AffinityLinux`
   - **Affinity installer:** **Download**, which fetches it from the official `downloads.affinity.studio`
   - **Wine version:** the recommended one (11.21 at the time of writing)
4. Windows-style setup windows (.NET, fonts, WebView2) will pop up. Let them finish, and click **Next**/**Install**/**Finish** if one waits for you.
5. If the installer asks for your `sudo` password even though step 1 installed everything, stop and check which step it's on before typing it.

When it finishes, you have an **Affinity** entry in your application menu.

> **Windows tiny or impossible to drag?** That's normal before step 3. To move a window you can't drag, hold the **Meta** (Windows) key and drag anywhere inside it, or press **Alt+F3** and choose **Move**.

## 3. Fix the interface size

Wine doesn't follow your desktop's display scaling. On a monitor scaled to more than 100%, Affinity looks tiny. Fix it by telling Wine the right DPI: **96 × your scale factor**.

| Display scale | DPI |
| --- | --- |
| 125% | 120 |
| 150% | 144 |
| 170% | 163 |
| 200% | 192 |

Find your scale in **System Settings → Display & Monitor** (KDE) or **Settings → Displays** (GNOME). Close Affinity, then run (replace `163` with your value):

```bash
export WINEPREFIX=~/.AffinityLinux
~/.AffinityLinux/ElementalWarriorWine/bin/wine reg add 'HKCU\Control Panel\Desktop' \
  /v LogPixels /t REG_DWORD /d 163 /f
~/.AffinityLinux/ElementalWarriorWine/bin/wineserver -k
```

The last command stops Wine so the change applies on the next start. Open Affinity again; if it's now too big or too small, repeat with a different value.

A quicker but blurrier alternative on KDE: **System Settings → Display & Monitor → Legacy Applications (X11) → Scaled by the system**.

## 4. Install the connector

```bash
git clone https://github.com/sandeepsubba/canva-linux-connector.git
cd canva-linux-connector
bin/canva-affinity setup --force --dry-run   # optional: shows what it would change
./install.sh --force
```

`--force` is needed with Linux-Affinity-Installer because the installer registers its own `affinity://` handler, which can't complete the sign-in (see [Troubleshooting](TROUBLESHOOTING.md#no-such-file-affinitycanvaauthorize-and-affinity-stays-signed-out)). Without `--force`, setup stops and explains instead of replacing it.

Setup prints a ✓ line for each piece. Then check everything:

```bash
~/.local/bin/canva-affinity doctor
```

The last line should be **"Everything needed for Canva sign-in is in place."**

> **Tip:** to type `canva-affinity` without the `~/.local/bin/` part, add that folder to your `PATH`. fish: `fish_add_path ~/.local/bin`. bash/zsh: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` or `~/.zshrc` and open a new terminal.

## 5. Sign in to Canva

1. **Fully close Affinity** and open it again from the application menu, so it starts with the new setup.
2. Click **Sign in**. Your browser opens Canva.
3. Sign in to Canva with the account that has your subscription.
4. The browser hands the `affinity://` link to the desktop:
   - **"Open Affinity?" in the browser:** click **Open**.
   - **KDE "Choose Application" window** listing the long `affinity://canva/authorize?code=…` link: select **Affinity Canva sign-in**, tick **Set as default app to open files**, and click **OK**. Don't choose "Affinity sign-in handler"; that's the installer's handler.
5. Affinity shows you as signed in.

The link in that window contains a one-time sign-in code. It expires within minutes and works only once, but don't post screenshots of it publicly before then.

> **A Canva page saying "We can't show this page – Error: 403" in a small browser popup?** That's Canva's Google login popup, not the connector. If Affinity already shows you as signed in, close it. If not, see [Troubleshooting](TROUBLESHOOTING.md#canva-shows-we-cant-show-this-page--error-403).

## 6. Use the AI tools

Once you're signed in with an account whose Canva plan includes them, Affinity's Canva AI tools (Generative Fill, Remove Background, Expand and others) become available. They run on Canva's servers through your account.

- **Tools missing or locked:** check which account Affinity shows. Sign out and in again with the subscribed account.
- **A blank panel or an error in an AI tool:** some panels use WebView2, which is less reliable under Wine. See [Troubleshooting](TROUBLESHOOTING.md#an-ai-tool-or-panel-is-blank-or-shows-an-error). The same tools also work on [canva.com](https://www.canva.com) in your browser; you can bring the result into Affinity.

## 7. Keeping it working

- **After updating Affinity or Wine,** run `canva-affinity doctor`. If anything shows ✗, run `canva-affinity setup` (with `--force` if the installer re-registered its handler).
- **After re-running Linux-Affinity-Installer** (for example its Canva sign-in repair), its own handler may be the default again. `doctor` will say so; run `./install.sh --force` again.
- **To update the connector:**

  ```bash
  cd canva-linux-connector
  git pull
  ./install.sh --force
  ```

- **To remove it:** see [Uninstall](../README.md#uninstall).
