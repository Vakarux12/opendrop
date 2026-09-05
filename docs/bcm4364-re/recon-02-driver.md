# BCM4364 recon #2 — the driver half is OPEN SOURCE (read-only review)

Driver: `brcmfmac` from kernel **7.1.3** = exactly the running kernel
(`7.1.3-arch1-Watanare-T2-2-t2`). Reviewed files (vanilla upstream, fetched
2026-09-05 into `/tmp`, not vendored here):
`drivers/net/wireless/broadcom/brcm80211/brcmfmac/{cfg80211.c,feature.c,feature.h,fwil.c}`

## 1. Your `feature_disable=0x82000`, decoded

`feature.h` builds `enum brcmf_feat_id` in list order (bit N = 1<<N):
MBSS=0 MCHAN=1 PNO=2 WOWL=3 P2P=4 RSDB=5 TDLS=6 SCAN_RANDOM_MAC=7 WOWL_ND=8
WOWL_GTK=9 WOWL_ARP_ND=10 MFP=11 GSCAN=12 FWSUP=13 MONITOR=14 MONITOR_FLAG=15
MONITOR_FMT_RADIOTAP=16 **MONITOR_FMT_HW_RX_HDR=17** DOT11H=18 **SAE=19** …

`0x82000` = bits 17+19 = T2 setup disables **MONITOR_FMT_HW_RX_HDR + SAE**
(HW_RX_HDR has no fwcap probe — FWID-quirk only, see below — so this is
belt-and-braces for BCM4364).

## 2. How monitor mode gets advertised (or doesn't)

- `feature.c` `brcmf_fwcap_map`: firmware capability string `"monitor"` →
  `BRCMF_FEAT_MONITOR`, `"rtap"` → `MONITOR_FLAG` + `MONITOR_FMT_RADIOTAP`
  (probed from FW via `cap` iovar at attach).
- `brcmf_feat_fwfeat_map` (FWID quirks): only `01-6cb8e269` (43602) and
  `01-c47a91a4` (4366b) force `MONITOR`; two 4366 FWIDs force
  `MONITOR_FMT_HW_RX_HDR`. **Our `01-c06f991b` is not listed** → no override.
- `cfg80211.c` `brcmf_setup_ifmodes()` (~line 7478): `mon_flag =
  feat(MONITOR_FLAG)` gates `BIT(NL80211_IFTYPE_MONITOR)` in
  `wiphy->interface_modes` plus combo limits. No flag → `iw list` shows no
  monitor (exactly what we observe).
- Monitor datapath code **already exists**: `brcmf_alloc_vif(...MONITOR...)`
  (~line 921), add/del/change handlers (~lines 995-1011, 1320-1340, 1393+).

## 3. Why this is good news

Upstream `brcmfmac` monitor support is gated, not absent — and our firmware
contains `wlc_monitor_attach` + `monitor_promisc_level` (recon-01). Open
question is only whether FW 9.30.503 honors the monitor/promisc iovars the
driver sends. That is testable **without flashing firmware**.

## 4. Driver-only experiment plan (no firmware mods)

1. User live-tests `docs/bcm4364-re/restore-wifi.sh` (proves recovery).
2. Backup `.ko`s: done — `brcmfmac.ko.zst` + `brcmutil.ko.zst` are in
   `~/.local/share/bcm4364-wifi-backup/` (add to any module-restore step).
3. Minimal patch to try first (1 line + rebuild):
   in `brcmf_feat_fwfeat_map`, add
   `{ "01-c06f991b", BIT(BRCMF_FEAT_MONITOR) },`
   and if needed also set `MONITOR_FLAG` via fwcap override. Rebuild just
   `brcmfmac.ko` against `/usr/src/linux-t2` headers, install as depmod
   override, reload, check `iw list` for `monitor`, then
   `iw phy <phy> interface add mon0 type monitor`.
4. If `mon0` comes up: test RX (`tcpdump -i mon0`) and TX injection —
   success = OWL becomes possible on internal Wi-Fi.
5. If FW ignores the iovars: next step is Ghidra on the 0x160000 anchor
   (recon-01) + read-only ROM dump to find what `monitor_promisc_level`
   gates. Firmware patching is plan B, not plan A.

## 5. Sudo-gated steps (only the machine owner can do these)

- `restore-wifi.sh` live run (password prompt, drops Wi-Fi ~30s)
- build deps (`base-devel` etc.), module build/install, `iw`/`mon0` tests,
  debugfs read of `brcmfmac` features (`/sys/kernel/debug/...`, root-only)
