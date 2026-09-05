#!/usr/bin/env python3
"""ble-airdrop-wake.py - broadcast Apple AirDrop BLE advertisements (type 0x05)
to wake nearby iPhones' AWDL stack. No Wi-Fi impact (separate radio).

Payload (furiousMAC/continuity, Discontinued Privacy paper):
  05 12 | 8x00 | 01 | 2B appleID | 2B phone | 2B email | 2B email2 | 00
Hashes are zeroed: fine for Everyone-mode receivers (nothing to match).

Usage: ./ble-airdrop-wake.py [seconds]   (0 = until killed)
Needs permission for BlueZ advertising (user session or root).
"""
import sys
import signal

import dbus
import dbus.service
import dbus.mainloop.glib

try:
    from gi.repository import GLib
except ImportError:
    import gobject as GLib  # type: ignore

BUS = "org.bluez"
AD_PATH = "/com/example/airdropwake0"
HCI = "/org/bluez/hci0"

# AirDrop wake TLV: type 0x05, len 0x12 (=18 payload bytes after header),
# total 20 bytes on air after the company ID.
PAYLOAD = bytes([0x05, 0x12] + [0x00] * 8 + [0x01] + [0x00] * 8 + [0x00])
assert len(PAYLOAD) == 20, len(PAYLOAD)


class Advertisement(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, AD_PATH)

    def get_path(self):
        return dbus.ObjectPath(AD_PATH)

    @dbus.service.method("org.freedesktop.DBus.Properties",
                         in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != "org.bluez.LEAdvertisement1":
            raise dbus.exceptions.DBusException("unknown interface")
        return {
            # broadcast = non-connectable (like Apple's); must NOT set
            # Discoverable with this type or BlueZ rejects the packet.
            "Type": dbus.String("broadcast", variant_level=1),
            "ManufacturerData": dbus.Dictionary(
                {dbus.UInt16(0x004C): dbus.Array(
                    [dbus.Byte(b) for b in PAYLOAD],
                    signature="y", variant_level=1)},
                signature="qv", variant_level=1),
        }

    @dbus.service.method("org.bluez.LEAdvertisement1", in_signature="",
                         out_signature="")
    def Release(self):
        print("advertisement released", flush=True)


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    Advertisement(bus)
    mgr = dbus.Interface(bus.get_object(BUS, HCI),
                         "org.bluez.LEAdvertisingManager1")

    loop = GLib.MainLoop()

    def stop(*_a):
        try:
            mgr.UnregisterAdvertisement(AD_PATH)
        except Exception:
            pass
        loop.quit()
        return False

    signal.signal(signal.SIGTERM, lambda *a: stop())
    signal.signal(signal.SIGINT, lambda *a: stop())
    mgr.RegisterAdvertisement(
        AD_PATH, {},
        reply_handler=lambda: print("AirDrop BLE wake advertising "
                                    f"({len(PAYLOAD)}B type 0x05)", flush=True),
        error_handler=lambda e: (print(f"register failed: {e}", flush=True),
                                 loop.quit()))
    if secs > 0:
        GLib.timeout_add_seconds(secs, stop)
    loop.run()


if __name__ == "__main__":
    main()
