#!/usr/bin/env python3
"""驗證翻譯、機型文字、權限說明與文件連結。

用法：python3 scripts/check-resources.py
輸入：Sources、Package.swift、根目錄 Markdown 與技能入口。
讀取本機檔案，使用 macOS plutil 解析翻譯，失敗時指出缺少的內容。
"""

import json
import plistlib
import re
import subprocess
import urllib.parse
from pathlib import Path

# 確認 App 宣告、資源目錄與套件的預設語言一致。
root = Path(__file__).resolve().parent.parent
resources = root / 'Sources/Resources'
info = plistlib.loads((resources / 'Info.plist').read_bytes())
languages = {p.stem for p in resources.glob('*.lproj')}
assert languages == set(info['CFBundleLocalizations']), '宣告語系與資源目錄不一致'
assert info['CFBundleDevelopmentRegion'] in languages, '預設語系缺少資源'
package_locale = re.search(
    r'defaultLocalization:\s*"([^"]+)"',
    (root / 'Package.swift').read_text(),
)
assert (
    package_locale
    and package_locale.group(1) == info['CFBundleDevelopmentRegion']
), '套件與 App 預設語系不一致'

# 逐一解析一般翻譯與系統權限文案，空白內容視為缺少翻譯。
translations = {}
for language in sorted(languages):
    for filename in ['Localizable.strings', 'InfoPlist.strings']:
        path = resources / f'{language}.lproj' / filename
        translated_plist = subprocess.check_output(
            ['plutil', '-convert', 'xml1', '-o', '-', str(path)]
        )
        data = plistlib.loads(translated_plist)
        assert all(isinstance(v, str) and v.strip() for v in data.values()), f'空白翻譯：{path}'
        # 一般翻譯保存供比對，權限翻譯檢查必要說明鍵。
        if filename == 'Localizable.strings':
            translations[language] = data
        else:
            required_permission_keys = {
                'NSBluetoothAlwaysUsageDescription',
                'NSAudioCaptureUsageDescription',
            }
            assert required_permission_keys <= data.keys(), (
                f'缺少藍牙或系統音訊權限文案：{path}'
            )

# 各語系使用相同翻譯鍵，後續來源檢查共用這份鍵集合。
translation_key_sets = [set(value) for value in translations.values()]
assert all(
    key_set == translation_key_sets[0]
    for key_set in translation_key_sets
), '各語系的翻譯鍵不一致'

# 從 Swift 介面宣告與動態標籤方法擷取需要翻譯的文字。
visible_keys = set()
quoted_text_pattern = r'"([^"\\]*(?:\\.[^"\\]*)*)"'
view_text_pattern = (
    r'\b(?:Text|Button|Toggle|Picker|LabeledContent|Section|ProgressView|Link|'
    r'confirmationDialog|accessibilityLabel)\(\s*'
    + quoted_text_pattern
)
localized_text_pattern = r'String\(localized:\s*' + quoted_text_pattern
label_method_pattern = (
    r'\b(?:var|func)\s+'
    r'(?:displayName|descriptionKey|titleKey|loginStatusText|bluetoothStatus|actionTitle)'
    r'\b[^{}]*\{'
)
returned_text_pattern = r'(?:case[^:\n]*:|return)\s*' + quoted_text_pattern
for source in (root / 'Sources').rglob('*.swift'):
    text = source.read_text()
    visible_keys.update(re.findall(view_text_pattern, text))
    visible_keys.update(re.findall(localized_text_pattern, text))
    # 方法體可能含巢狀區塊，以大括號深度找到完整內容。
    for declaration in re.finditer(label_method_pattern, text):
        start = declaration.end()
        depth = 1
        end = start
        while depth and end < len(text):
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        body = text[start:end - 1]
        visible_keys.update(re.findall(returned_text_pattern, body))
# 插值文字交由翻譯資源本身處理，靜態文字逐一核對。
visible_keys = {key for key in visible_keys if key and '\\(' not in key}
assert visible_keys <= translation_key_sets[0], (
    f'缺少介面翻譯：{visible_keys - translation_key_sets[0]}'
)

# 機型配置提供的配色、診斷與開發狀態文字也需要翻譯。
for profile in (resources / 'Profiles').glob('*.json'):
    data = json.loads(profile.read_text())
    required = {color['label'] for color in data['colors']}
    required |= {check['labelKey'] for check in data['diagnosticChecks']}
    required |= {'research.' + feature['id'] for feature in data['developmentFeatures']}
    required |= {feature['reasonKey'] for feature in data['developmentFeatures']}
    assert required <= translation_key_sets[0], (
        f'缺少配置的動態翻譯：{profile}: {required - translation_key_sets[0]}'
    )

# 技能別名必須指向同一份 .ai，讓協作規則維持一致。
for alias in ['.claude', '.agents', '.codex']:
    path = root / alias
    assert path.is_symlink() and path.resolve() == (root / '.ai').resolve(), (
        f'技能入口失效：{alias}'
    )
print(f'通過：{len(translation_key_sets[0])} 個翻譯鍵、機型文字、權限文案與技能入口')

# 文件僅檢查本機連結，外部網址與頁內錨點維持原樣。
for document in root.glob('*.md'):
    content = re.sub(r'```.*?```', '', document.read_text(), flags=re.S)
    for link in re.findall(r'\]\(([^)]+)\)', content):
        target = link.split('#', 1)[0]
        # 空目標與外部網址不屬於檔案存在性檢查。
        if not target or urllib.parse.urlparse(target).scheme:
            continue
        decoded_target = urllib.parse.unquote(target)
        assert (document.parent / decoded_target).exists(), (
            f'文件連結失效：{document.name}: {target}'
        )
print('通過：根目錄 Markdown 連結與預設語言設定')
