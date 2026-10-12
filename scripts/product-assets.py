#!/usr/bin/env python3
"""驗證或下載機型配置引用的產品圖片。

用法：python3 scripts/product-assets.py [--download]
來源：Products/sources.json 的網址與 SHA-256，以及 Profiles 的圖片範圍。
預設讀取本機圖片；--download 驗證下載內容後，才取代本機圖片。
"""

import argparse
import hashlib
import json
import struct
import urllib.request
from pathlib import Path

# 路徑從腳本位置推導，讓命令可在任意工作目錄執行。
root = Path(__file__).resolve().parent.parent
products_folder = root / "Sources/Resources/Products"
profiles_folder = root / "Sources/Resources/Profiles"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--download",
    action="store_true",
    help="依來源清單重新下載，SHA-256 相符後才寫入本機",
)
arguments = parser.parse_args()

# 來源以檔名索引，同名來源視為清單錯誤。
manifest = json.loads((products_folder / "sources.json").read_text())
sources_by_filename = {item["file"]: item for item in manifest}
assert len(sources_by_filename) == len(manifest), "素材來源清單包含重複檔名"
referenced_filenames = set()

# 逐一檢查每款機型、配色與耳機／充電盒圖片。
for profile_path in sorted(profiles_folder.glob("*.json")):
    profile = json.loads(profile_path.read_text())
    for color in profile["colors"]:
        for image_kind in ["earbuds", "chargingCase"]:
            asset = color[image_kind]
            filename = asset["name"] + ".png"
            assert filename in sources_by_filename, f"缺少圖片來源：{filename}"
            source = sources_by_filename[filename]
            image_path = products_folder / filename

            # 下載內容先核對來源雜湊，避免將上游變動寫入本機。
            if arguments.download:
                with urllib.request.urlopen(source["url"], timeout=30) as response:
                    downloaded_image = response.read()
                downloaded_hash = hashlib.sha256(downloaded_image).hexdigest()
                assert downloaded_hash == source["sha256"], (
                    f"上游素材內容已變動：{filename}"
                )
                image_path.write_bytes(downloaded_image)

            # 本機圖片同時檢查雜湊、PNG 標頭及配置的可見矩形。
            image_data = image_path.read_bytes()
            image_hash = hashlib.sha256(image_data).hexdigest()
            assert image_hash == source["sha256"], f"素材雜湊不一致：{filename}"
            assert image_data[:8] == b"\x89PNG\r\n\x1a\n", f"圖片格式不是 PNG：{filename}"

            image_width, image_height = struct.unpack(">II", image_data[16:24])
            left, top, crop_width, crop_height = asset["bounds"]
            assert (
                0 <= left < image_width
                and 0 <= top < image_height
                and crop_width > 0
                and crop_height > 0
            ), f"可見矩形的起點或尺寸無效：{filename}"
            assert (
                left + crop_width <= image_width
                and top + crop_height <= image_height
            ), f"可見矩形超出圖片：{filename}"
            referenced_filenames.add(filename)

# 配置、來源清單與實際圖片目錄必須涵蓋相同檔案。
assert referenced_filenames == set(sources_by_filename), "來源清單包含未使用素材"
local_filenames = {path.name for path in products_folder.glob("*.png")}
assert referenced_filenames == local_filenames, "素材目錄與配置清單不一致"
print(f"通過：{len(referenced_filenames)} 張產品圖片、雜湊、可見範圍與來源清單")
