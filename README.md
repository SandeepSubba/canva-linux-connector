# Canva ↔ Affinity connector for Linux

Use the Canva AI tools from your Canva plan in **Affinity by Canva** running on Linux under Wine.

Affinity's AI tools, such as Generative Fill, Remove Background and Expand, only unlock once you sign in with your Canva account. On Linux that sign-in normally breaks: you finish logging in to Canva in your browser, but Affinity never finds out. This connector fixes that hand-off.

```bash
git clone https://github.com/sandeepsubba/canva-linux-connector.git
cd canva-linux-connector
./install.sh
```

Then restart Affinity, click **Sign in**, and finish signing in to Canva in your browser.

New to running Affinity on Linux? Follow the **[step-by-step guide](docs/GUIDE.md)**. It starts from a fresh system and ends with Affinity signed in.

## Documentation

| | |
| --- | --- |
| [Guide](docs/GUIDE.md) | Install Affinity under Wine, fix the interface size, set up the connector and sign in. |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Symptoms and fixes, from "No such file" to Canva's 403 page. |
| [How it works](docs/HOW-IT-WORKS.md) | What breaks under Wine, what the connector changes, and where it writes. |
| [Changelog](CHANGELOG.md) | What changed in each version. |

## What you need first

1. **Affinity by Canva (v3) installed under Wine.** Canva has said a native Linux version is in development but hasn't shipped it. Until then, the easiest route is [Linux-Affinity-Installer](https://github.com/ryzendew/Linux-Affinity-Installer). It bundles a Wine build that's patched for Affinity. Setups from the [AffinityOnLinux](https://github.com/seapear/AffinityOnLinux) guides, Bottles and Lutris work too.
2. **A Canva plan that includes the AI features** (e.g. Canva Pro). Affinity itself is free; the AI tools come from your Canva subscription.
3. A few common tools: `curl`, `7z`, `xdg-utils`, `xz`.
   - Debian/Ubuntu: `sudo apt install curl p7zip-full xdg-utils xz-utils`
   - Fedora: `sudo dnf install curl p7zip p7zip-plugins xdg-utils xz`
   - Arch: `sudo pacman -S curl 7zip xdg-utils xz`

## Usage

```text
canva-affinity setup       Fix the Canva sign-in (run once; safe to re-run)
canva-affinity doctor      Check every piece and say what's missing
canva-affinity paste       Fallback: paste the affinity:// link from your browser
canva-affinity launch      Start Affinity with the right Wine
canva-affinity uninstall   Remove the link handler (--purge also removes config/logs)
```

`install.sh` puts the command in `~/.local/bin`. If that folder isn't on your `PATH`, run it as `~/.local/bin/canva-affinity`, or add the folder to your shell (fish: `fish_add_path ~/.local/bin`; bash/zsh: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` or `~/.zshrc`).

The connector finds your Affinity install on its own. If you have more than one, or it lives somewhere unusual, pass `--prefix`:

```bash
canva-affinity setup --prefix ~/.local/share/bottles/bottles/Affinity
```

Use `--dry-run` with any command to see what it would change without changing anything.

### Using Linux-Affinity-Installer?

That installer registers its own `affinity://` handler, which passes the link to its `affinity-on-linux.exe` launcher. That launcher opens documents, not links: it reports `No such file: affinity://…` and Affinity stays signed out. Setup leaves other apps' handlers alone by default, so replace it once with:

```bash
./install.sh --force
```

Don't point `--exe` at `affinity-on-linux.exe`. Setup refuses it since 1.1.0, and the connector starts `Affinity.exe` directly instead.

## Signing in

1. Run `canva-affinity doctor`. Everything should show ✓.
2. Open Affinity and click **Sign in**. Your browser opens Canva.
3. Sign in to Canva. When the browser or desktop asks which app should open the link, choose **Affinity Canva sign-in**. On KDE, also tick **Set as default app** so it doesn't ask again.
4. Affinity shows you as signed in, and the Canva AI tools become available.

If step 4 doesn't happen, see [Troubleshooting](docs/TROUBLESHOOTING.md). The short version:

- Click **Sign in** again for a fresh link; each one works once and expires within minutes.
- Run `canva-affinity paste`, copy the `affinity://…` link from the browser's "Open Affinity?" prompt, and paste it in. The link isn't shown or saved.
- Check the logs in `~/.local/state/canva-affinity-connector/`. Link secrets are never written to them.
- Run `canva-affinity doctor` and follow the hints.

## What it fixes

When you finish signing in, Canva sends a long `affinity://…` link (about 1,700 characters) back to the app. Under Wine, several things go wrong with that link:

| Problem | What the connector does |
| --- | --- |
| Wine's own link handler uses `wine start`, which crashes on links longer than about 300 characters. | It registers its own `affinity://` handler. The handler starts `Affinity.exe` directly with the link. If Affinity is already running, that second copy forwards the link to it and exits. |
| Some installers' handlers pass the link to a launcher that only opens files, so it fails with "No such file". | It detects those handlers, explains the problem in `setup` and `doctor`, and never uses such a launcher itself. |
| Affinity's link-reading code needs two .NET files (`System.Runtime.WindowsRuntime` and `…UI.Xaml`). `winetricks dotnet48` doesn't install them, so a running Affinity **crashes** when the link arrives. | It extracts both files from Microsoft's official .NET 4.8 installer and checks them against known SHA-256 hashes. Then it adds them to the Wine prefix's .NET library folder (the GAC). |
| Older Wine builds also need Windows metadata (`.winmd`) files. | It installs those for Wine 9 and 10. For Wine 11 builds that read metadata, it installs only the combined `Windows.winmd`. The archive is checked against a SHA-256 hash. |

Setup also:

- Points Wine's own `affinity://` registry entry at the right `.exe`.
- Sets WebView2 (used by Affinity's Help and some web panels) to Windows 7 mode, which keeps it working under Wine.

### Safety

- **No root access.** Setup only changes files in your home folder and your Wine prefix.
- **No silent takeover.** If another app already handles `affinity://` links (from Bottles, Lutris or another installer), setup leaves it alone unless you pass `--force`.
- **No crash-prone handler.** If your Wine version can't complete the sign-in, setup won't register the handler. A forwarded link would crash a running Affinity and you could lose work. Doctor tells you what to change.
- **Only `affinity://` links are forwarded,** as a single argument and never through a shell. The config file is read as plain text and never run as code.
- **No secrets in logs.** `handler.log` records only the link's scheme and path. Wine's and Affinity's output, which can echo the whole link, goes to `wine.log` with the link's query and any `code=`, `token=`, `state=` or `exchangeId=` values replaced by `<hidden>`.

## Which Wine versions work

| Wine | Sign-in |
| --- | --- |
| ElementalWarrior 9.x / 10.x (e.g. 10.10) | ✓ with this connector |
| Affinity-patched 11.18+ (Linux-Affinity-Installer's 11.20 / 11.21) | ✓ with this connector (tested with 11.21) |
| Upstream Wine 11.19+ (reads WinMetadata) | ✓ should work. Run `doctor` to confirm. |
| Other Wine 11 builds | ✗ Doctor says so. Switch Wine, or use the LoginFix plugin (below). |
| Wine 10.17 | Avoid it; it has known bugs that break Affinity. |

**Plan B: the LoginFix plugin.** If you can't change your Wine version, the [AffinityOnLinux](https://github.com/seapear/AffinityOnLinux/wiki/Login-Solution-and-Scripts) project has a LoginFix plugin for AffinityPluginLoader. It works around the crash instead. The connector notices AffinityPluginLoader and launches `AffinityHook.exe`, so plugins load when the link starts Affinity.

## Config

Setup saves what it detected to `~/.config/canva-affinity-connector/config`:

```ini
PREFIX="/home/you/.AffinityLinux"
WINE="/home/you/.AffinityLinux/ElementalWarriorWine/bin/wine"
EXE="/home/you/.AffinityLinux/drive_c/Program Files/Affinity/Affinity/Affinity.exe"
# Extra environment for Affinity, space separated:
WINE_ENV="WINEDLLOVERRIDES=d3d9=n,b"
```

If an older config points `EXE` at a launcher that can't take links, the connector ignores it, uses `Affinity.exe` and says so. Re-run `canva-affinity setup` to rewrite the config.

## Limits

- **Unofficial.** Canva doesn't support Affinity under Wine. An Affinity or Wine update can break things; re-run `canva-affinity doctor` after updating either.
- **Sign-in only.** The connector fixes sign-in. The AI tools then run on Canva's servers through your account. Any Affinity panel that depends on WebView2 can still be unreliable under Wine.
- **Flatpak or Snap browsers** hand the link to the desktop through a portal, which normally works. If it doesn't, use `canva-affinity paste`.

## Uninstall

```bash
canva-affinity uninstall --purge
rm ~/.local/bin/canva-affinity
```

The .NET and metadata files added to the Wine prefix stay. They're harmless, and other tools expect them.

## Development

```bash
tests/run-tests.sh                  # runs with a fake Wine and prefix; no network needed
shellcheck -x bin/canva-affinity install.sh
shellcheck -x -P SCRIPTDIR/.. tests/run-tests.sh
```

CI runs both on every push and pull request. See [How it works](docs/HOW-IT-WORKS.md) for the design and the test setup.

## Credits

The fixes come from community work on running Affinity on Linux:

- [Linux-Affinity-Installer](https://github.com/ryzendew/Linux-Affinity-Installer): the WinRT facade and URL handler fix ([PR #223](https://github.com/ryzendew/Linux-Affinity-Installer/pull/223)), and the WinMetadata archive.
- [AffinityOnLinux](https://github.com/seapear/AffinityOnLinux): the LoginFix plugin and the manual paste-link approach.
- [AffinityPluginLoader / WineFix](https://github.com/noahc3/AffinityPluginLoader): the Wine fixes and the analysis in [issue #59](https://github.com/noahc3/AffinityPluginLoader/issues/59).
- ElementalWarrior's Wine builds for Affinity.

Affinity and Canva are trademarks of Canva Pty Ltd. This project isn't affiliated with or endorsed by Canva.

## License

MIT
