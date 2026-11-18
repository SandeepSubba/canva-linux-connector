# How it works

This page explains what happens during a Canva sign-in, why it breaks under Wine, and exactly what the connector changes. It's for anyone who wants to check the connector before running it, debug it, or contribute.

## The sign-in flow

```text
Affinity (Wine)            Browser                      Linux desktop               Connector
──────────────            ───────                      ─────────────               ─────────
1. Sign in ─────────────▶ 2. canva.com login
                          3. Canva redirects to
                             affinity://canva/authorize?code=…&exchangeId=…
                                    │
                                    └────────────────▶ 4. xdg-open / portal
                                                          looks up the handler for
                                                          x-scheme-handler/affinity
                                                                 │
                                                                 └──────────────▶ 5. canva-affinity handle <link>
                                                                                     checks it, logs a redacted line,
                                                                                     starts: wine Affinity.exe <link>
6. A second Affinity.exe starts, finds the running one,
   passes it the link over a named pipe, and exits.
7. The running Affinity reads the link, exchanges the code with Canva,
   and shows you as signed in.
```

The link is about 1,700 characters long and contains a one-time code (a signed JWT) plus an `exchangeId`. It's valid once, for a few minutes.

## What breaks under Wine

| Step | Problem |
| --- | --- |
| 4 → 5 | With no handler, nothing receives the link. Wine generates `wine-protocol-affinity.desktop`, which runs `wine start <link>`, and `wine start` crashes on links longer than about 300 characters. |
| 4 → 5 | Linux-Affinity-Installer registers `affinity-url-handler.desktop`, which runs its `affinity-on-linux.exe` launcher with `%F %u`. That launcher opens documents: it treats the link as a file name and prints `No such file: affinity://…`. Affinity never gets the link. |
| 6 → 7 | Affinity reads the link through Windows Runtime (WinRT) APIs. `winetricks dotnet48` leaves out the .NET facades for them (`System.Runtime.WindowsRuntime` and `System.Runtime.WindowsRuntime.UI.Xaml`), so the running Affinity crashes when the link arrives. |
| 6 → 7 | Some Wine builds also need Windows metadata (`.winmd`) files to resolve the WinRT types involved. |

## What setup changes

`canva-affinity setup` resolves three things, in order: command-line flags, then the config file, then auto-detection.

- **Prefix:** `$WINEPREFIX`, then common locations (`~/.AffinityLinux`, `~/.affinity`, the AppImage prefix, Lutris, `~/.wine`), then Bottles.
- **Wine:** the prefix's bundled `ElementalWarriorWine/bin/wine` or `wine/bin/wine`, a Bottles runner, or the system `wine`.
- **Executable:** `AffinityHook.exe` if AffinityPluginLoader is installed (so plugins load on a cold start), otherwise `Affinity.exe`. Launchers that can't take links (currently `affinity-on-linux.exe`) are refused for `--exe` and ignored, with a warning, if an older config contains them.

Then it makes these changes. Everything is inside your home folder or the Wine prefix; nothing needs root.

| What | Where | Why |
| --- | --- | --- |
| Config | `~/.config/canva-affinity-connector/config` | Remembers prefix, Wine, `.exe` and extra environment. Parsed as `KEY=value` text, never sourced. |
| .NET WinRT facades | `<prefix>/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL/…` | Extracted from Microsoft's .NET 4.8 offline installer (SHA-256 checked), then each DLL is checked against its own SHA-256 before it's copied. The installer is cached in the winetricks cache. |
| Windows metadata | `<prefix>/drive_c/windows/system32/WinMetadata/` | Wine 9/10: all `.winmd` files. Wine 11 builds that resolve metadata: only the combined `Windows.winmd`, because per-namespace files shadow it and break opening documents from the command line. Archive SHA-256 checked. |
| Registry | `HKCU\Software\Classes\affinity\shell\open\command` | Points Wine's own protocol entry at the real `.exe`. |
| Registry | `HKCU\Software\Wine\AppDefaults\msedgewebview2.exe` → `Version=win7` | Keeps WebView2 (Help and some Canva panels) working under Wine. |
| Link handler | `~/.local/share/applications/canva-affinity-handler.desktop` | `Exec=<path to canva-affinity> handle %u`, `MimeType=x-scheme-handler/affinity;`, hidden from menus. |
| Default handler | via `xdg-mime default`, or `~/.config/mimeapps.list` directly | Makes the connector the default for `affinity://`. Only replaces no handler, its own, or Wine's generated one, unless `--force`. |
| Wine's generated handler | moved to `~/.local/state/canva-affinity-connector/wine-protocol-affinity.desktop.bak` | Wine regenerates it, and it would otherwise win the default again. |

Setup checks whether your Wine can complete the callback before registering anything:

- Wine 9.x and 10.x: supported.
- Wine 11+: supported if its `wintypes.dll` resolves WinRT namespaces from WinMetadata, or if the per-namespace login metadata is present. Otherwise unsupported, and the handler isn't registered (a forwarded link would crash a running Affinity) unless you pass `--force`.

## What `handle` does

`canva-affinity handle <link>` is what the desktop runs when a browser opens an `affinity://` link.

1. Rejects anything that isn't `affinity://…`, contains a line break, or is longer than 32,768 characters.
2. Appends one line to `handler.log`: time, the link with everything after `?`/`#` replaced by `<N chars hidden>`, its length, and the `.exe` it will start.
3. Starts `env WINEPREFIX=… [WINE_ENV…] WINEDEBUG=-all <wine> <exe> <link>`, with the link as one argument and no shell in between. It's detached with `setsid` (or `nohup`) so the browser isn't left waiting.
4. Pipes Wine's and Affinity's output through `redact_stream` into `wine.log`. Launchers and Affinity can print the whole link, so the filter hides everything after `?`/`#` in `affinity://` links and the values of `code=`, `token=`, `access_token=`, `id_token=`, `state=` and `exchangeId=`.

If Affinity is already running, the new `Affinity.exe` forwards the link to it and exits. If not, it starts Affinity with the link.

## Other commands

| Command | What it does |
| --- | --- |
| `doctor` | Read-only checks: prefix, Wine version, .NET 4.8, facades, WinMetadata, callback support, and who handles `affinity://` links. Exits non-zero if anything needed is missing. |
| `paste` | Reads a link without echoing it (`read -s`) and passes it to `handle`. For when the browser can't hand the link to the desktop. |
| `launch` | Starts Affinity with the configured Wine, `.exe` and environment. |
| `uninstall` | Removes the handler file and the `affinity://` default; `--purge` also removes config and logs. Files added to the prefix stay. |

Every command accepts `--dry-run`, which prints what it would change without changing anything.

## Tests

`tests/run-tests.sh` runs every `test_*` function in a throwaway `HOME` with a fake Affinity prefix and a fake `wine` script. The fake `wine` answers `--version`, logs `reg` calls, and records its arguments, so tests can check exactly what would have run. With `FAKE_ECHO=1` it also prints the link on stdout and stderr, like `affinity-on-linux.exe` does, to test log redaction. No network or real Wine is needed.

```bash
tests/run-tests.sh            # everything
tests/run-tests.sh handle     # only tests whose name contains "handle"
```

CI (GitHub Actions) runs ShellCheck on all scripts and then the tests, on every push and pull request.
