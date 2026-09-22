#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
umask 077
pkg install -y openssh python
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.local/lib/qrbridge" "$HOME/bin" "$HOME/.shortcuts"
install -m 700 "$source_dir/client.py" "$HOME/.local/lib/qrbridge/client.py"
opener="$HOME/bin/termux-url-opener"
if [[ -e "$opener" ]] && ! grep -q 'QRBRIDGE_MANAGED' "$opener"; then
  cp -p "$opener" "$opener.before-qrbridge"
fi
cat > "$opener" <<'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# QRBRIDGE_MANAGED
set -euo pipefail
if [[ "${1:-}" == https://qrbridge.invalid/enroll\#* || "${1:-}" == http://100.*:8080/enroll\#* ]]; then
  exec python "$HOME/.local/lib/qrbridge/client.py" "$1"
elif [[ -x "$HOME/bin/termux-url-opener.before-qrbridge" ]]; then
  exec "$HOME/bin/termux-url-opener.before-qrbridge" "$@"
else
  printf '%s\n' 'Unsupported URL' >&2
  exit 1
fi
SCRIPT
cat > "$PREFIX/bin/windows" <<'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
config="$HOME/.ssh/qrbridge/config"
[[ -f "$config" ]] || { echo 'Scan and share an enrollment QR to Termux first.' >&2; exit 1; }
if [[ "${1:-}" == '--reconnect' ]]; then
  trap 'exit 0' INT TERM
  delay=1
  while true; do
    started=$SECONDS
    ssh -t -F "$config" windows && exit 0
    sleep "$delay"
    if (( SECONDS - started > 60 )); then delay=1; elif (( delay < 30 )); then delay=$((delay * 2)); fi
  done
fi
if (( $# )); then exec ssh -F "$config" windows "$@"; fi
exec ssh -t -F "$config" windows
SCRIPT
chmod 700 "$opener" "$PREFIX/bin/windows"
cat > "$HOME/.shortcuts/Windows-PowerShell" <<'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
exec windows --reconnect
SCRIPT
chmod 700 "$HOME/.shortcuts/Windows-PowerShell"
echo 'Ready. Scan the host QR, open its pairing page, copy the pairing command and paste it into Termux.'
