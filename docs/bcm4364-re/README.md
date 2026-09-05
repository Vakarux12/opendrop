# BCM4364 reverse-engineering notes (MacBookPro16,x, chip BCM4364/4)

Working baseline (Arch, T2 kernel):
- Driver: `brcmfmac`, firmware `brcmfmac4364b3-pcie`
- FW version: `BCM4364/4 wl0: Jul 10 2023 12:53:18 version 9.30.503.0.32.5.92 FWID 01-c06f991b`
- Options: `brcmfmac.feature_disable=0x82000 roamoff=1` (modprobe + kernel cmdline)
- Upstream `brcmfmac` (fullmac) lists **monitor mode as TODO** — no AWDL without firmware work.
- Nexmon supports bcm4330/4339/43438/4358/4356/43455 — **not** BCM4364. Porting = find
  `wlc_monitor`/`wlc_mctrl` hooks in 9.30.503 firmware (Ghidra ARM-Thumb), write
  `monitormode.c`-style patches. Months-scale project, Seemoo-Lab-sized.
- `broadcom-wl-dkms 6.30.223.271` predates BCM4364 (no `14e4:4464`) — no `prism0` shortcut.

## Safety net

Backup of the working set: `~/.local/share/bcm4364-wifi-backup/` (108 files, SHA256SUMS).
Firmware loads from `/lib/firmware/brcm/` into chip RAM every boot — macOS untouched.

- Verify backup (safe, no changes): `./restore-wifi.sh --check`
- Full restore + driver reload (drops Wi-Fi ~10-30s, needs sudo):
  `./restore-wifi.sh`
- Worst case: reboot — firmware reloads from disk on every boot.
