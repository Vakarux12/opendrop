#!/usr/bin/env bash
# airdrop-10s-test: 10s AWDL discoverability test, then auto-restore Wi-Fi.
set -u

NAME="ArchLinux"       # name iPhones will see
WINDOW=10              # discoverable seconds (use 120 for real hunting)
AP_IF=wlan0
MON_IF=awdlmon0
OWL_BIN=/usr/local/bin/owl   # fork build with -m MAC override
OWL_MAC=$(cat /sys/class/net/$AP_IF/address 2>/dev/null || echo "16:7d:da:27:be:b5")
OWL_LOG=/tmp/airdrop-10s-owl.log
OD_LOG=/tmp/airdrop-10s-opendrop.log
OWL_PID=""; OD_PID=""

# --- sudo keep-alive (no popups; uses $SUDO_PASS) ---
sudo_unlock() {
  sudo -n true 2>/dev/null && return 0
  [[ -n "${SUDO_PASS:-}" ]] || { echo "need sudo (set SUDO_PASS)"; return 1; }
  echo "$SUDO_PASS" | sudo -S -v 2>/dev/null
}
sudo_unlock || exit 1
( while kill -0 $$ 2>/dev/null; do sleep 50; sudo -n -v 2>/dev/null || break; done ) &
KA_PID=$!

cleanup() {
  echo "--- window over, restoring Wi-Fi ---"
  kill $OWL_PID $OD_PID 2>/dev/null; sleep 1
  kill -9 $OWL_PID $OD_PID 2>/dev/null; sleep 1
  sudo ip link set $MON_IF down 2>/dev/null
  sudo iw dev $MON_IF del 2>/dev/null
  # safety: wlan0 must be managed type for NetworkManager
  if [ "$(iw dev $AP_IF info 2>/dev/null | awk '/type/ {print $2}')" != "managed" ]; then
    sudo iw dev $AP_IF set type managed 2>/dev/null || true
  fi
  sudo systemctl restart NetworkManager
  for i in $(seq 1 20); do
    [ "$(nmcli -t -f STATE general 2>/dev/null)" = "connected" ] && break
    sleep 3
  done
  systemctl --user start opendrop-receive.service 2>/dev/null
  GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -n1)
  if ping -c2 -W3 "$GW" >/dev/null 2>&1; then echo "WIFI_BACK ($GW reachable)"; else echo "WARN: no gateway yet, wait 30s"; fi
  kill $KA_PID 2>/dev/null
}
trap cleanup EXIT

echo "== stopping infra receiver, taking $AP_IF down =="
systemctl --user stop opendrop-receive.service 2>/dev/null
sudo ip link set $AP_IF down
sleep 2
PHY=$(iw dev $AP_IF info 2>/dev/null | awk '/wiphy/ {print "phy"$2}')
[ -z "$PHY" ] && { echo "no phy for $AP_IF"; exit 1; }
echo "phy=$PHY"
# NOTE: OWL sets monitor mode itself and fails on brcmfmac (-N skips that,
# but then the iface must ALREADY be monitor type). Pre-create mon0 DOWN
# with a proper MAC (brcmfmac won't let us change it afterwards).
MON_MAC="16:7d:da:27:be:b5"
sudo iw dev $MON_IF del 2>/dev/null || true
sudo iw phy "$PHY" interface add $MON_IF type monitor addr $MON_MAC 2>/dev/null \
  || sudo iw phy "$PHY" interface add $MON_IF type monitor
echo "pre-made: $(ip -brief link show $MON_IF)"

wait_awdl0() {
  for i in $(seq 1 12); do
    ip link show awdl0 >/dev/null 2>&1 && [ -n "$(ip -6 -o addr show dev awdl0 scope link 2>/dev/null)" ] && return 0
    sleep 1
  done
  return 1
}

echo "== OWL attempt 1: -N -m $OWL_MAC -i $MON_IF =="
sudo -n $OWL_BIN -N -m "$OWL_MAC" -i $MON_IF >$OWL_LOG 2>&1 &
OWL_PID=$!
if wait_awdl0; then
  echo "awdl0 via $MON_IF"
else
  echo "attempt 1 failed: $(grep -m1 ERROR $OWL_LOG)"
  kill $OWL_PID 2>/dev/null; sleep 1; kill -9 $OWL_PID 2>/dev/null
  sudo iw dev $MON_IF del 2>/dev/null
  echo "== OWL attempt 2: -i $AP_IF (OWL owns monitor setup) =="
  sudo -n owl -i $AP_IF >>$OWL_LOG 2>&1 &
  OWL_PID=$!
  if wait_awdl0; then
    echo "awdl0 via $AP_IF"
  else
    echo "attempt 2 failed: $(grep -m1 ERROR $OWL_LOG)"
    echo "full owl log:"; cat $OWL_LOG
    exit 1
  fi
fi
ip -brief addr show awdl0

echo "== starting opendrop on awdl0 =="
opendrop receive -i awdl0 -n "$NAME" >$OD_LOG 2>&1 &
OD_PID=$!
sleep 2
grep -q "Announcing service" $OD_LOG && tail -n 2 $OD_LOG || { echo "opendrop failed:"; cat $OD_LOG; exit 1; }

echo ""
echo "***** DISCOVERABLE as '$NAME' for $WINDOW s *****"
for i in $(seq "$WINDOW" -1 1); do echo -n "$i... "; sleep 1; done
echo ""
echo "done."
