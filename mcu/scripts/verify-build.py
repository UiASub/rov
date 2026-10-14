#!/usr/bin/env python3
"""Check generated slot geometry, watchdog configuration and image signature."""
import os
from pathlib import Path
import pickle
import re
import sys

PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = Path(os.environ.get("ZEPHYR_WORKSPACE", PROJECT / ".zephyr")).resolve()
sys.path.insert(0, str(WORKSPACE / "zephyr/scripts/dts/python-devicetree/src"))
sys.path.insert(0, str(WORKSPACE / "bootloader/mcuboot/scripts"))
sys.path.insert(0, str(PROJECT / "scripts"))
from imgtool import keys
from imgtool.image import Image, VerifyResult
from ota import image_hash


def configuration(image):
    path = PROJECT / f"build-ota/{image}/zephyr/.config"
    return dict(re.findall(r"^(CONFIG_\w+)=(.*)$", path.read_text(), re.MULTILINE))


def verify():
    expected = {"boot_partition": (0, 0x20000),
                "slot0_partition": (0x20000, 0x60000),
                "slot1_partition": (0x100000, 0x80000)}
    for image, chosen in (("mcuboot", "boot_partition"), ("mcu", "slot0_partition")):
        edt = pickle.loads((PROJECT / f"build-ota/{image}/zephyr/edt.pickle").read_bytes())
        for label, geometry in expected.items():
            node = edt.label2node[label]
            assert [(reg.addr, reg.size) for reg in node.regs] == [geometry], (image, label)
        assert edt.chosen_nodes["zephyr,code-partition"] is edt.label2node[chosen]
        assert edt.get_node("watchdog0").status == "okay"
        config = configuration(image)
        assert config["CONFIG_WATCHDOG"] == "y"
        assert config["CONFIG_IWDG_STM32_INITIAL_TIMEOUT"] == "8000"
        assert config.get("CONFIG_WDT_DISABLE_AT_BOOT", "n") == "n"
    boot = configuration("mcuboot")
    app = configuration("mcu")
    assert boot["CONFIG_BOOT_SWAP_USING_OFFSET"] == "y"
    assert boot["CONFIG_BOOT_WATCHDOG_FEED"] == "y"
    assert boot["CONFIG_BOOT_SIGNATURE_TYPE_RSA"] == "y"
    assert app["CONFIG_MCUMGR_TRANSPORT_UDP"] == "y"
    assert app["CONFIG_MCUMGR_TRANSPORT_UDP_PORT"] == "1337"
    assert app["CONFIG_MCUMGR_GRP_IMG"] == "y"
    assert app["CONFIG_MCUMGR_GRP_OS"] == "y"
    assert app["CONFIG_ROV_OTA_CONFIRM"] == "y"
    image = PROJECT / "build-ota/mcu/zephyr/zephyr.signed.bin"
    key_path = boot["CONFIG_BOOT_SIGNATURE_KEY_FILE"].strip('"')
    assert key_path == app["CONFIG_MCUBOOT_SIGNATURE_KEY_FILE"].strip('"')
    result, version, digest, _ = Image.verify(str(image), keys.load(key_path))
    assert result == VerifyResult.OK, result
    assert digest.hex() == image_hash(image)
    footer = int(app["CONFIG_MCUBOOT_UPDATE_FOOTER_SIZE"], 0)
    assert image.stat().st_size <= expected["slot0_partition"][1] - footer
    assert (PROJECT / "build-ota/mcuboot/zephyr/zephyr.bin").stat().st_size <= expected["boot_partition"][1]
    print(f"Slot geometry, watchdogs and RSA signature verified; version {version}, {image.stat().st_size} bytes.")


if __name__ == "__main__":
    verify()
