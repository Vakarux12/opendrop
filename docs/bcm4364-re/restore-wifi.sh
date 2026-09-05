#!/usr/bin/env bash
# restore-wifi.sh - recover BCM4364 Wi-Fi after a bad firmware experiment.
# Runs locally, no internet needed (only pings the LAN gateway at the end).
# Usage:
#   ./restore-wifi.sh --check    verify backup integrity, change nothing
#   ./restore-wifi.sh            restore firmware + reload driver (needs sudo)
set -u

BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/bcm4364-wifi-backup}"
FW_DIR="/lib/firmware/brcm"
GATEWAY="$(ip route show default 2>/dev/null | awk '{print $3}' | head -n1)"

if [[ "${1:-}" == "--check" ]]; then
    echo "== backup integrity =="
    [[ -d "$BACKUP_DIR" ]] || { echo "MISSING backup dir: $BACKUP_DIR"; exit 1; }
    (cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS) | tail -n 3
    echo "backup files: $(ls "$BACKUP_DIR"/brcmfmac4364* 2>/dev/null | wc -l)"
    echo "modprobe conf backed up: $(test -f "$BACKUP_DIR/brcmfmac.conf" && echo yes || echo no)"
    echo "check done (nothing changed)"
    exit 0
fi

echo "== restoring BCM4364 firmware from $BACKUP_DIR =="
[[ -d "$BACKUP_DIR" ]] || { echo "MISSING backup dir: $BACKUP_DIR"; exit 1; }

echo "[1/5] restoring firmware files (sudo)..."
sudo cp -a "$BACKUP_DIR"/brcmfmac4364* "$FW_DIR"/
if [[ -f "$BACKUP_DIR/brcmfmac.conf" ]]; then
    sudo cp -a "$BACKUP_DIR/brcmfmac.conf" /etc/modprobe.d/brcmfmac.conf
fi

echo "[2/5] verifying checksums..."
(cd "$FW_DIR" && sudo sha256sum -c "$BACKUP_DIR/SHA256SUMS") | tail -n 2

echo "[3/5] reloading driver (Wi-Fi will drop for ~10-30s)..."
sudo modprobe -r brcmfmac brcmutil 2>/dev/null || sudo modprobe -r brcmfmac || true
sleep 2
sudo modprobe brcmfmac
sleep 3

echo "[4/5] restarting NetworkManager..."
sudo systemctl restart NetworkManager
for i in $(seq 1 30); do
    state="$(nmcli -t -f STATE general 2>/dev/null)"
    [[ "$state" == "connected" ]] && break
    sleep 2
done

echo "[5/5] verifying..."
iw dev 2>/dev/null | grep -A2 wlan0 | head -n 5 || ip link show wlan0
if [[ -n "$GATEWAY" ]] && ping -c2 -W3 "$GATEWAY" >/dev/null 2>&1; then
    echo "OK: gateway $GATEWAY reachable, Wi-Fi restored"
else
    echo "WARN: gateway ${GATEWAY:-unknown} not reachable yet - wait 30s and retry,"
    echo "or reboot (firmware reloads from $FW_DIR on every boot)"
    exit 1
fi
