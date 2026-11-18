# Troubleshooting

Start with:

```bash
canva-affinity doctor
```

It checks every piece the sign-in needs and prints a hint for anything that's missing. Most problems are fixed by `canva-affinity setup` (add `--force` if another app owns the `affinity://` handler).

## Where to look

| File | What's in it |
| --- | --- |
| `~/.local/state/canva-affinity-connector/handler.log` | One line per link the connector received: time, `affinity://host/path?<N chars hidden>`, link length, and the `.exe` it started. Errors from the handler appear here too. |
| `~/.local/state/canva-affinity-connector/wine.log` | Output from Wine and Affinity for each link, with the link's query and any `code=`, `token=`, `state=` or `exchangeId=` values replaced by `<hidden>`. |
| `~/.config/canva-affinity-connector/config` | The prefix, Wine and `.exe` setup detected. |

Neither log contains the one-time sign-in code, so you can share them when asking for help. Look through them first anyway.

To watch what happens during a sign-in:

```bash
tail -f ~/.local/state/canva-affinity-connector/*.log
```

---

## "No such file: affinity://canva/authorize?…" and Affinity stays signed out

**Cause:** the link went to a launcher that opens documents, not links. Linux-Affinity-Installer's `affinity-on-linux.exe` does this: it treats the whole link as a file name. This happens when:

- the installer's own handler (`affinity-url-handler.desktop`) is still the default for `affinity://` links, or
- the connector was set up with `--exe …/affinity-on-linux.exe` (connector 1.0.0 allowed this).

**Fix:**

```bash
canva-affinity setup --force
```

Since 1.1.0, `doctor` reports the installer's handler as a problem, `setup --exe` refuses `affinity-on-linux.exe`, and an old config pointing at it is ignored with a warning. Leave `--exe` out unless you have a reason to set it; the connector picks `AffinityHook.exe` (if AffinityPluginLoader is installed) or `Affinity.exe`.

## KDE asks "Choose an application to open 'affinity://canva/authorize?…'"

The browser handed the link to KDE, and KDE wants to confirm which app should open it.

1. Select **Affinity Canva sign-in** (it's marked "Default app for this file type").
2. Tick **Set as default app to open files** so it doesn't ask again.
3. Click **OK**.

Don't choose **Affinity sign-in handler**. That's Linux-Affinity-Installer's handler; see the previous section.

## Canva shows "We can't show this page – Error: 403"

This shows up in a small browser popup at a `canva.com/oauth/authorized/google?…` address. It's Canva's **Google login popup**, which runs in the browser, before the link reaches the connector.

- **If Affinity already shows you as signed in,** the sign-in worked; close the popup.
- **If not,** click **Sign in** in Affinity again for a fresh attempt.
- **If it keeps happening,** it's likely the browser's privacy settings blocking Canva's Google popup. In Brave, turn off **Shields** for canva.com (the lion icon in the address bar) and try again. You can also sign in to Canva with email and password instead of "Continue with Google".

## The link was handed over, but nothing happened in Affinity

1. **The link expired.** Each sign-in link works once, within a few minutes. Click **Sign in** in Affinity again.
2. **Check the log:** `handler.log` should show a `handle affinity://canva/authorize?<… chars hidden>` line at the time you signed in.
   - **No line:** the link never reached the connector. Run `canva-affinity doctor` and check the "affinity:// links are handled by…" line. If your browser runs as a Flatpak or Snap, see below.
   - **A line, but no sign-in:** look at `wine.log` for errors from Wine or Affinity at that time.
3. **Use the manual fallback:**

   ```bash
   canva-affinity paste
   ```

   When the browser shows "Open Affinity?" (or nothing happens), copy the `affinity://` link it tried to open (right-click the button → **Copy link**, or copy it from the address bar), paste it in and press Enter. The link isn't shown or saved.

## Affinity crashes when the link arrives

The running Affinity can't read the link. Usually the .NET WinRT facades are missing, or your Wine build can't resolve WinRT metadata.

```bash
canva-affinity doctor
```

- **"WinRT facades missing"**: run `canva-affinity setup`.
- **"Sign-in callback: unsupported"**: your Wine build can't complete the sign-in. Switch to an Affinity-patched Wine (Linux-Affinity-Installer 11.20/11.21, or ElementalWarrior 10.10), or install the [LoginFix plugin](https://github.com/seapear/AffinityOnLinux/wiki/Login-Solution-and-Scripts).

Setup won't register the handler on a Wine it knows can't do this, because a forwarded link would crash a running Affinity and you could lose unsaved work.

## Setup says "affinity:// links are handled by '…' (another setup)"

Another app (Linux-Affinity-Installer, Bottles, Lutris…) registered its own handler, and setup doesn't replace other apps' handlers silently. If you want this connector to handle the sign-in:

```bash
canva-affinity setup --force
```

## Setup says "… can't take sign-in links"

You passed `--exe` pointing at a launcher that only opens documents (such as `affinity-on-linux.exe`). Leave `--exe` out, or point it at `Affinity.exe` or `AffinityHook.exe`.

## Affinity is tiny, or windows can't be dragged

Wine doesn't follow your desktop's display scaling. Set Wine's DPI to 96 × your scale factor; see [Guide, step 3](GUIDE.md#3-fix-the-interface-size).

To move a Wine window that won't drag, hold **Meta** (the Windows key) and drag anywhere inside it, or press **Alt+F3** and choose **Move** (KDE).

## An AI tool or panel is blank or shows an error

The connector's job ends once you're signed in. The AI tools then run on Canva's servers through your account, and some Affinity panels are drawn with WebView2, which is less reliable under Wine.

- Check that Affinity shows the account that has your Canva plan.
- Make sure `doctor` shows ✓ (setup sets WebView2 to Windows 7 mode, which helps).
- Restart Affinity.
- As a workaround, use the same tool on [canva.com](https://www.canva.com) and bring the result into Affinity.

## The browser is a Flatpak or Snap

Sandboxed browsers hand links to the desktop through a portal, which normally reaches the connector. If it doesn't, use `canva-affinity paste`.

## Still stuck?

Open an issue with:

- the output of `canva-affinity doctor`
- the relevant lines of `handler.log` and `wine.log` (secrets are already hidden, but check)
- your distribution, desktop and browser
- how you installed Affinity, and the Wine version
