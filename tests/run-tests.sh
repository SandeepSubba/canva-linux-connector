#!/usr/bin/env bash
# Tests for canva-affinity. No real Wine or network needed: each test gets a
# throwaway HOME with a fake Affinity prefix and a fake `wine` that records how
# it was called.
#
#   tests/run-tests.sh            run everything
#   tests/run-tests.sh handle     run tests whose name contains "handle"

set -o nounset -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/canva-affinity"
FILTER=${1:-}
PASS=0 FAIL=0
FAILED=()

# --------------------------------------------------------------- helpers ----

new_env() {
    T=$(mktemp -d)
    export HOME="$T/home"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
    export NO_COLOR=1
    unset WINEPREFIX XDG_CURRENT_DESKTOP DESKTOP_SESSION KDE_FULL_SESSION GNOME_DESKTOP_SESSION_ID
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/applications"
    PFX="$HOME/.AffinityLinux"
    make_prefix "$PFX"
    export FAKE_WINE_VERSION="10.10"
    export FAKE_ARGS="$T/wine-args" FAKE_LOG="$T/wine-log"
}

make_prefix() {
    local p=$1
    mkdir -p "$p/drive_c/Program Files/Affinity/Affinity" \
             "$p/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319" \
             "$p/drive_c/windows/system32" \
             "$p/ElementalWarriorWine/bin"
    : > "$p/drive_c/Program Files/Affinity/Affinity/Affinity.exe"
    : > "$p/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll"
    cat > "$p/ElementalWarriorWine/bin/wine" <<'EOF'
#!/usr/bin/env bash
# Fake wine: answer --version, log `reg` calls, record everything else.
if [[ "${1:-}" == --version ]]; then echo "wine-${FAKE_WINE_VERSION}"; exit 0; fi
if [[ "${1:-}" == reg ]]; then printf '%s\n' "$*" >> "$FAKE_LOG"; exit 0; fi
{ printf 'WINEPREFIX=%s\0' "${WINEPREFIX:-}"; printf 'EXTRA=%s\0' "${FAKE_EXTRA:-}"; printf '%s\0' "$@"; } > "$FAKE_ARGS"
EOF
    chmod +x "$p/ElementalWarriorWine/bin/wine"
}

seed_facades() {
    local p=${1:-$PFX} name
    for name in System.Runtime.WindowsRuntime System.Runtime.WindowsRuntime.UI.Xaml; do
        mkdir -p "$p/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL/$name/v4.0_4.0.0.0__b77a5c561934e089"
        : > "$p/drive_c/windows/Microsoft.NET/assembly/GAC_MSIL/$name/v4.0_4.0.0.0__b77a5c561934e089/$name.dll"
    done
}

seed_winmd() {
    local p=${1:-$PFX}
    mkdir -p "$p/drive_c/windows/system32/winmetadata"
    : > "$p/drive_c/windows/system32/winmetadata/Windows.Foundation.winmd"
}

# Setup that never touches the network: pieces are already in the prefix.
offline_setup() { seed_facades; seed_winmd; "$CLI" setup; }

default_handler() { xdg-mime query default x-scheme-handler/affinity 2>/dev/null; }

# Read the fake wine's recorded argv into the array ARGS.
read_args() { ARGS=(); while IFS= read -r -d '' a; do ARGS+=("$a"); done < "$FAKE_ARGS"; }

fail() { echo "    assertion failed: $*"; return 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]${3:+ ($3)}"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain [$2]; got: ${1:0:600}"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "output should not contain [$2]"; }
assert_file() { [[ -f "$1" ]] || fail "missing file $1"; }
assert_no_file() { [[ ! -e "$1" ]] || fail "file should not exist: $1"; }

run_test() {
    local name=$1
    [[ -z "$FILTER" || "$name" == *"$FILTER"* ]] || return 0
    new_env
    if ( set -o errexit; "$name" ) > "$T/out" 2>&1; then
        PASS=$((PASS + 1)); echo "ok   $name"
    else
        FAIL=$((FAIL + 1)); FAILED+=("$name"); echo "FAIL $name"; sed 's/^/    /' "$T/out"
    fi
    rm -rf "$T"
}

# ----------------------------------------------------------------- tests ----

test_help_and_version() {
    out=$("$CLI" help); assert_contains "$out" "Usage: canva-affinity"
    out=$("$CLI" version); assert_contains "$out" "canva-affinity 1."
    if "$CLI" bogus 2>/dev/null; then fail "unknown command should fail"; fi
}

test_doctor_reports_missing_pieces() {
    if out=$("$CLI" doctor 2>&1); then fail "doctor should fail on a fresh prefix"; fi
    assert_contains "$out" "WinRT facades missing"
    assert_contains "$out" "No handler for affinity://"
    assert_contains "$out" "Wine 10.10"
}

test_doctor_no_prefix() {
    rm -rf "$PFX"
    if out=$("$CLI" doctor 2>&1); then fail "should fail without Affinity"; fi
    assert_contains "$out" "No Affinity install found"
}

test_setup_registers_handler() {
    out=$(offline_setup 2>&1) || fail "setup failed: $out"
    local desktop="$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
    assert_file "$desktop"
    desktop-file-validate "$desktop" || fail "invalid desktop file"
    assert_contains "$(cat "$desktop")" "MimeType=x-scheme-handler/affinity;"
    assert_contains "$(cat "$desktop")" "Exec=$CLI handle %u"
    assert_eq "$(default_handler)" "canva-affinity-handler.desktop"
    assert_contains "$(cat "$XDG_CONFIG_HOME/canva-affinity-connector/config")" "PREFIX=\"$PFX\""
    # Registry: protocol command points at the real exe, WebView2 set to win7.
    log=$(cat "$FAKE_LOG")
    assert_contains "$log" 'HKCU\Software\Classes\affinity\shell\open\command'
    assert_contains "$log" '"C:\Program Files\Affinity\Affinity\Affinity.exe" "%1"'
    assert_contains "$log" 'msedgewebview2.exe /v Version /d win7'
    out=$("$CLI" doctor 2>&1) || fail "doctor should pass after setup: $out"
    assert_contains "$out" "Everything needed for Canva sign-in is in place"
}

test_setup_parks_wine_generated_handler() {
    local apps="$XDG_DATA_HOME/applications"
    printf '[Desktop Entry]\nType=Application\nName=Wine affinity\nExec=wine start %%u\nMimeType=x-scheme-handler/affinity;\n' > "$apps/wine-protocol-affinity.desktop"
    xdg-mime default wine-protocol-affinity.desktop x-scheme-handler/affinity
    offline_setup >/dev/null 2>&1 || fail "setup failed"
    assert_no_file "$apps/wine-protocol-affinity.desktop"
    assert_file "$XDG_STATE_HOME/canva-affinity-connector/wine-protocol-affinity.desktop.bak"
    assert_eq "$(default_handler)" "canva-affinity-handler.desktop"
}

test_setup_respects_other_handler_unless_forced() {
    local apps="$XDG_DATA_HOME/applications"
    printf '[Desktop Entry]\nType=Application\nName=Other\nExec=true %%u\nMimeType=x-scheme-handler/affinity;\n' > "$apps/affinity-url-handler.desktop"
    xdg-mime default affinity-url-handler.desktop x-scheme-handler/affinity
    if out=$(offline_setup 2>&1); then fail "setup should not take over silently"; fi
    assert_contains "$out" "handled by 'affinity-url-handler.desktop'"
    assert_eq "$(default_handler)" "affinity-url-handler.desktop"
    "$CLI" setup --force >/dev/null 2>&1 || fail "--force setup failed"
    assert_eq "$(default_handler)" "canva-affinity-handler.desktop"
}

test_setup_refuses_without_facades() {
    seed_winmd
    if out=$("$CLI" setup --no-facades 2>&1); then fail "should refuse without facades"; fi
    assert_contains "$out" "WinRT facades are missing"
    assert_no_file "$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
}

test_setup_unsupported_wine11_without_metadata() {
    export FAKE_WINE_VERSION="11.12"
    if out=$(offline_setup 2>&1); then fail "should refuse on stubbed Wine 11"; fi
    assert_contains "$out" "not supported here"
    assert_no_file "$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
}

test_setup_wine11_with_login_metadata() {
    export FAKE_WINE_VERSION="11.12"
    local d="$PFX/drive_c/windows/system32/winmetadata"
    mkdir -p "$d"
    : > "$d/windows.applicationmodel.datatransfer.winmd"
    : > "$d/Windows.Foundation.winmd"   # case differs on purpose
    : > "$d/windows.storage.streams.winmd"
    seed_facades
    out=$("$CLI" setup 2>&1) || fail "setup should pass: $out"
    assert_contains "$out" "login metadata"
}

test_setup_wine11_that_reads_winmetadata() {
    export FAKE_WINE_VERSION="11.21"
    local lib="$PFX/ElementalWarriorWine/lib/wine/x86_64-windows"
    mkdir -p "$lib"
    printf 'x\0W\0i\0n\0M\0e\0t\0a\0D\0a\0t\0a\0\0y' > "$lib/wintypes.dll"
    out=$(offline_setup 2>&1) || fail "setup should pass: $out"
    assert_contains "$out" "reads WinMetadata"
}

test_handle_passes_link_verbatim() {
    offline_setup >/dev/null 2>&1
    url='affinity://auth/callback?code=SECRET123&state=a%20b&x="q"'
    "$CLI" handle --foreground "$url" || fail "handle failed"
    read_args
    assert_eq "${ARGS[0]}" "WINEPREFIX=$PFX"
    assert_eq "${ARGS[2]}" "$PFX/drive_c/Program Files/Affinity/Affinity/Affinity.exe"
    assert_eq "${ARGS[3]}" "$url" "link must arrive as one unchanged argument"
    assert_eq "${#ARGS[@]}" 4
    log=$(cat "$XDG_STATE_HOME/canva-affinity-connector/handler.log")
    assert_contains "$log" "affinity://auth/callback?<"
    assert_not_contains "$log" "SECRET123"
}

test_handle_long_link() {
    offline_setup >/dev/null 2>&1
    url="affinity://signin?token=$(head -c 2400 /dev/zero | tr '\0' 'a')"
    "$CLI" handle --foreground "$url" || fail "handle failed"
    read_args
    assert_eq "${#ARGS[3]}" "${#url}"
}

test_handle_background_mode() {
    offline_setup >/dev/null 2>&1
    "$CLI" handle "affinity://x?y=1" || fail "handle failed"
    for _ in $(seq 50); do [[ -s "$FAKE_ARGS" ]] && break; sleep 0.1; done
    read_args
    assert_eq "${ARGS[3]}" "affinity://x?y=1"
}

test_browser_handoff_via_xdg_open() {
    # What a browser does after sign-in: xdg-open the affinity:// link.
    offline_setup >/dev/null 2>&1
    url="affinity://login/callback?code=TOPSECRET&state=xyz"
    BROWSER=false DISPLAY=:99 xdg-open "$url" || fail "xdg-open failed"
    for _ in $(seq 50); do [[ -s "$FAKE_ARGS" ]] && break; sleep 0.1; done
    read_args
    assert_eq "${ARGS[3]:-}" "$url"
    assert_not_contains "$(cat "$XDG_STATE_HOME/canva-affinity-connector/handler.log")" "TOPSECRET"
}

test_handle_rejects_other_schemes() {
    offline_setup >/dev/null 2>&1
    if "$CLI" handle --foreground "https://evil.example/" 2>/dev/null; then fail "should reject https"; fi
    if "$CLI" handle --foreground $'affinity://a\nb' 2>/dev/null; then fail "should reject newlines"; fi
    assert_no_file "$FAKE_ARGS"
    assert_contains "$(cat "$XDG_STATE_HOME/canva-affinity-connector/handler.log")" "Not an affinity:// link"
}

test_handle_prefers_affinityhook() {
    : > "$PFX/drive_c/Program Files/Affinity/Affinity/AffinityHook.exe"
    offline_setup >/dev/null 2>&1
    "$CLI" handle --foreground "affinity://x" || fail "handle failed"
    read_args
    assert_eq "${ARGS[2]}" "$PFX/drive_c/Program Files/Affinity/Affinity/AffinityHook.exe"
}

test_wine_env_from_config() {
    offline_setup >/dev/null 2>&1
    local cfg="$XDG_CONFIG_HOME/canva-affinity-connector/config"
    sed -i 's|^WINE_ENV=.*|WINE_ENV="FAKE_EXTRA=d3d9=n,b* not-valid"|' "$cfg"
    "$CLI" handle --foreground "affinity://x" 2>/dev/null || fail "handle failed"
    read_args
    assert_eq "${ARGS[1]}" "EXTRA=d3d9=n,b*"
}

test_config_is_not_executed() {
    offline_setup >/dev/null 2>&1
    local cfg="$XDG_CONFIG_HOME/canva-affinity-connector/config"
    # shellcheck disable=SC2016  # literal $(...) on purpose
    echo 'EXE="$(touch '"$T"'/pwned)"' >> "$cfg"
    "$CLI" doctor >/dev/null 2>&1 || true
    assert_no_file "$T/pwned"
}

test_prefix_with_spaces() {
    local p="$HOME/My Wine/affinity prefix"
    make_prefix "$p"; seed_facades "$p"; seed_winmd "$p"
    out=$("$CLI" setup --prefix "$p" 2>&1) || fail "setup failed: $out"
    "$CLI" handle --foreground "affinity://z" || fail "handle failed"
    read_args
    assert_eq "${ARGS[0]}" "WINEPREFIX=$p"
}

test_exec_path_quoting() {
    # A copy of the tool in a folder with a space must be quoted in Exec=.
    local dir="$HOME/my tools"
    mkdir -p "$dir"; cp "$CLI" "$dir/canva-affinity"
    seed_facades; seed_winmd
    "$dir/canva-affinity" setup >/dev/null 2>&1 || fail "setup failed"
    local desktop="$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
    assert_contains "$(cat "$desktop")" "Exec=\"$dir/canva-affinity\" handle %u"
    desktop-file-validate "$desktop" || fail "invalid desktop file"
}

test_uninstall() {
    offline_setup >/dev/null 2>&1
    "$CLI" uninstall --purge >/dev/null 2>&1 || fail "uninstall failed"
    assert_no_file "$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
    assert_not_contains "$(cat "$XDG_CONFIG_HOME/mimeapps.list" 2>/dev/null)" "canva-affinity-handler"
    assert_no_file "$XDG_CONFIG_HOME/canva-affinity-connector"
}

test_mimeapps_editing_keeps_other_entries() {
    # shellcheck source=bin/canva-affinity
    source "$CLI"
    printf '[Added Associations]\ntext/plain=gedit.desktop;\n\n[Default Applications]\nimage/png=eog.desktop;\nx-scheme-handler/affinity=old.desktop;\n' > "$MIMEAPPS"
    mimeapps_set "canva-affinity-handler.desktop"
    content=$(cat "$MIMEAPPS")
    assert_contains "$content" "text/plain=gedit.desktop;"
    assert_contains "$content" "image/png=eog.desktop;"
    assert_contains "$content" "x-scheme-handler/affinity=canva-affinity-handler.desktop;"
    assert_not_contains "$content" "old.desktop"
    mimeapps_set ""
    assert_not_contains "$(cat "$MIMEAPPS")" "x-scheme-handler/affinity"
    assert_contains "$(cat "$MIMEAPPS")" "image/png=eog.desktop;"
    # No [Default Applications] section yet.
    printf '[Added Associations]\ntext/plain=gedit.desktop;\n' > "$MIMEAPPS"
    mimeapps_set "canva-affinity-handler.desktop"
    assert_contains "$(cat "$MIMEAPPS")" $'[Default Applications]\nx-scheme-handler/affinity=canva-affinity-handler.desktop;'
}

test_redact_url() {
    # shellcheck source=bin/canva-affinity
    source "$CLI"
    assert_eq "$(redact_url 'affinity://a/b?code=123')" "affinity://a/b?<9 chars hidden>"
    assert_eq "$(redact_url 'affinity://a/b')" "affinity://a/b"
}

test_dry_run_changes_nothing() {
    seed_facades; seed_winmd
    "$CLI" setup --dry-run >/dev/null 2>&1 || fail "dry run failed"
    assert_no_file "$XDG_DATA_HOME/applications/canva-affinity-handler.desktop"
    assert_no_file "$XDG_CONFIG_HOME/canva-affinity-connector/config"
    assert_no_file "$FAKE_LOG"
}

# ------------------------------------------------------------------- run ----

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done
echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || { printf '  %s\n' "${FAILED[@]}"; exit 1; }
