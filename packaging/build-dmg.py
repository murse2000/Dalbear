import subprocess
import sys
from pathlib import Path

import dmgbuild
from ds_store import DSStore
from mac_alias import Bookmark

mount_path = None


def mounted(path, options):
    global mount_path
    mount_path = Path(path)


def progress(event):
    if event.get("type") == "operation::finished" and event.get("operation") == "dsstore::create":
        # 현재 macOS에서 해석할 수 있는 배경 참조를 Foundation으로 생성합니다.
        data = subprocess.check_output([
            ".build/dmg-bookmark", str(mount_path / ".background.tiff")
        ])
        with DSStore.open(str(mount_path / ".DS_Store"), "r+") as store:
            store["."]["pBBk"] = Bookmark.from_bytes(data)
        subprocess.run(["codesign", "--verify", "--strict", str(mount_path / "Dalbear.app")], check=True)


dmgbuild.build_dmg(
    sys.argv[1], "Dalbear", settings_file="packaging/dmg-settings.py",
    settings={"create_hook": mounted}, callback=progress,
)
