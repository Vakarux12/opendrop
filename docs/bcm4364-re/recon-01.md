# BCM4364 recon #1 — firmware fingerprint + first anchor (read-only)

Date: 2026-09-05. No flashing, no reloads, no sudo used. All work on a
backup copy in `~/.local/share/bcm4364-wifi-backup/`.

## Image

- File: `brcmfmac4364b3-pcie.apple,trinidad.bin` (820013 bytes)
- Version string: `4364b3-roml/config_pcie_release_sdb_udm Version:
  9.30.503.0.32.5.92 CRC: 52521606 Date: Mon 2023-07-10 12:55:46 PDT
  Ucode Ver: 1088.50124 FWID: 01-c06f991b`
- Chip rev **B3**, `roml` = patch-RAM image over chip ROM (not a full image —
  most code lives in ROM, this file only overlays it).
- Offset 0x0 disassembles cleanly as Thumb-2: dual `b.w` vector tables
  (HNDRTE bootloader style). So: ARM Cortex-R4 / Thumb-2, raw RAM image.

## Monitor code is present

- `wlc_monitor_attach` string at file offset **0x8fdb6**
- `monitor_promisc_level` string at file offset **0x686b8**
- (Only 2 `monitor` + 1 `promisc` string hits total — monitor exists but is
  not a prominent/compiled-in-everywhere feature.)

## Link base candidate: 0x160000

Brute-forced 7 candidate Broadcom RAM bases for a pointer to the
`wlc_monitor_attach` string. Exactly one hit: with base **0x160000**,
file offset **0x86cfc** holds `0x001efdb6` = string address.

Disassembly at base 0x160000 shows 0x86cfc is a literal pool for real code:
function starting `push {r4,r5,r6,lr}` at file 0x86c94 (`ldr r2,[pc,#0x48]`
loads the string pointer, then `bl` into a compare/dispatch helper).
Pattern matches an attach-time name lookup — anchor for the monitor path.

## What this means

- Base 0x160000 is the working hypothesis for full disassembly (Ghidra:
  ARM Cortex, Thumb-2, base 0x160000, mirror size 0x100000+ for ROM later).
- The `.bin` alone is insufficient: `roml` means callees (e.g. targets of
  the `bl`s at 0x86c9e/0x86cac/0x86cda) live in **chip ROM**. Next step is a
  ROM dump (root: `/dev/mem` or `dhdutil`-style mem read — NOT done here).
- Driver side (`brcmfmac`) also needs work: upstream lists monitor mode as
  TODO for fullmac; needs interface-type + iovar plumbing even if FW cooperates.

## Next steps (need sudo / user action)

1. User runs `docs/bcm4364-re/restore-wifi.sh` live once (proves recovery).
2. Install RE tools: `yay -S ghidra radare2` (or Flatpak Ghidra) + 32-bit
   nexmon toolchain libs for later patch builds.
3. Ghidra project: import `.bin` at 0x160000, analyze, locate `wlc_monitor_attach`
   function via the 0x86cfc anchor; find `wlc_mctrl`/`MONITOR_*` flag handling.
4. ROM dump (root, read-only) to resolve ROM callees.
5. Only then: patch design (nexmon `monitormode.c` pattern for 43455 as template),
   tested with restore script on standby.

## Repro

```bash
FW=~/.local/share/bcm4364-wifi-backup/brcmfmac4364b3-pcie.apple,trinidad.bin
xxd -l 64 "$FW"                       # vector table
strings -n 8 "$FW" | grep -i monitor  # wlc_monitor_attach @ 0x8fdb6
python3 -c "import capstone"          # capstone 5.0.7 used for disasm above
```
