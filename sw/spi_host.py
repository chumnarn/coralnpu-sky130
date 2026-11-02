#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
spi_host.py - load and run a CoralNPU ELF through the chip's SPI port.

Back-ends
  --hex FILE        write {addr,data} pairs for the RTL test-bench
                    (tb/tb_soc.v with +PROG=FILE, see 'make sim-real')
  --ftdi URL        drive a real chip with an FT232H/FT2232H (pip install pyftdi)
                    e.g. --ftdi ftdi://ftdi:232h/1
  --dry-run         just print the SPI transactions

SPI protocol (mode 0, MSB first, f_sck <= f_clk/16), see rtl/soc/spi_axi_bridge.v
  0x02 A3..A0 D3..D0          WRITE32
  0x03 A3..A0 xx Q3..Q0       READ32   (xx = status byte)
  0x05 S                      STATUS
  0x9F I3..I0                 READ_ID  (0x434E5055 "CNPU")

Boot sequence: load segments -> CSR+4 = entry -> CSR+0 = 1 -> CSR+0 = 0
CSR base: 0x0003_0000 (full variant) / 0x0020_0000 (lite variant)
"""
import argparse
import struct
import sys
import time

CMD_WRITE, CMD_READ, CMD_STATUS, CMD_ID = 0x02, 0x03, 0x05, 0x9F
CHIP_ID = 0x434E5055
CSR_BASE = {"full": 0x00030000, "lite": 0x00200000}


# ----------------------------------------------------------------- ELF loading
def load_elf(path):
    """Return (entry, [(addr, bytes), ...]) for PT_LOAD segments (ELF32 LE)."""
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        sys.exit(f"{path}: not a little-endian ELF32 file")
    (e_entry, e_phoff) = struct.unpack_from("<II", data, 24)
    (e_phentsize, e_phnum) = struct.unpack_from("<HH", data, 42)
    segs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, _vaddr, p_paddr, p_filesz, _memsz = struct.unpack_from("<IIIIII", data, off)
        if p_type == 1 and p_filesz > 0:  # PT_LOAD
            segs.append((p_paddr, data[p_offset:p_offset + p_filesz]))
    return e_entry, segs


def words(segs):
    for base, blob in segs:
        blob = blob + b"\x00" * (-len(blob) % 4)
        for i in range(0, len(blob), 4):
            yield base + i, struct.unpack_from("<I", blob, i)[0]


# ----------------------------------------------------------------- transports
class DryRun:
    def xfer(self, out):
        print("SPI >", " ".join(f"{b:02X}" for b in out))
        return bytes(len(out))


class Ftdi:
    def __init__(self, url, freq):
        from pyftdi.spi import SpiController  # pip install pyftdi
        self.ctrl = SpiController()
        self.ctrl.configure(url)
        self.port = self.ctrl.get_port(cs=0, freq=freq, mode=0)

    def xfer(self, out):
        return self.port.exchange(out, duplex=True)


class Chip:
    def __init__(self, link):
        self.link = link

    def write32(self, addr, value):
        self.link.xfer(bytes([CMD_WRITE]) + addr.to_bytes(4, "big") + value.to_bytes(4, "big"))

    def read32(self, addr):
        r = self.link.xfer(bytes([CMD_READ]) + addr.to_bytes(4, "big") + bytes(5))
        return int.from_bytes(r[6:10], "big"), r[5]

    def status(self):
        return self.link.xfer(bytes([CMD_STATUS, 0]))[1]

    def chip_id(self):
        return int.from_bytes(self.link.xfer(bytes([CMD_ID]) + bytes(4))[1:5], "big")


def decode_status(s):
    names = ["halted", "fault", "wfi", "alive", "read_late", "overrun", "resp_err", "busy"]
    return ", ".join(n for i, n in enumerate(names) if s >> i & 1) or "-"


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("elf")
    ap.add_argument("--variant", choices=CSR_BASE, default="full")
    ap.add_argument("--csr-base", type=lambda x: int(x, 0))
    ap.add_argument("--hex", help="write test-bench program file")
    ap.add_argument("--ftdi", help="pyftdi URL of the SPI adapter")
    ap.add_argument("--freq", type=float, default=1e6, help="SPI clock (Hz), <= f_clk/16")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verify", action="store_true", help="read back every word")
    ap.add_argument("--timeout", type=float, default=5.0)
    a = ap.parse_args()

    csr = a.csr_base if a.csr_base is not None else CSR_BASE[a.variant]
    entry, segs = load_elf(a.elf)
    prog = list(words(segs))
    print(f"[spi_host] {a.elf}: entry 0x{entry:08x}, {len(prog)} words in {len(segs)} segment(s)")
    for base, blob in segs:
        print(f"           segment 0x{base:08x} .. 0x{base + len(blob):08x}")

    boot = [(csr + 4, entry), (csr + 0, 1), (csr + 0, 0)]

    if a.hex:
        with open(a.hex, "w") as f:
            for addr, val in prog + boot:
                f.write(f"{addr:08x}{val:08x}\n")
            f.write("ffffffffffffffff\n")  # end marker
        print(f"[spi_host] wrote {a.hex} ({len(prog) + len(boot)} transactions)")
        return

    link = DryRun() if (a.dry_run or not a.ftdi) else Ftdi(a.ftdi, a.freq)
    chip = Chip(link)
    if not a.dry_run:
        cid = chip.chip_id()
        print(f"[spi_host] chip id 0x{cid:08x} {'OK' if cid == CHIP_ID else 'MISMATCH'}")
        if cid != CHIP_ID:
            sys.exit(1)
    for addr, val in prog:
        chip.write32(addr, val)
    if a.verify and not a.dry_run:
        bad = 0
        for addr, val in prog:
            got, _ = chip.read32(addr)
            if got != val:
                bad += 1
                print(f"  verify 0x{addr:08x}: 0x{got:08x} != 0x{val:08x}")
        print(f"[spi_host] verify: {bad} mismatches")
    for addr, val in boot:
        chip.write32(addr, val)
    if a.dry_run:
        return
    t0 = time.time()
    while time.time() - t0 < a.timeout:
        s = chip.status()
        if s & 0x3:
            break
        time.sleep(0.01)
    print(f"[spi_host] status: {decode_status(s)}")
    # The GPIO block sits on the core's AXI *manager* port, so the host cannot
    # read it over SPI - look at the gpio_out pads / LEDs instead.


if __name__ == "__main__":
    main()
