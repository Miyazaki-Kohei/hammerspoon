# hammerspoon

macOS の [Hammerspoon](https://www.hammerspoon.org/) 設定（`~/.hammerspoon`）。

## 構成

| ファイル | 内容 |
|---|---|
| `init.lua` | エントリポイント。`hs` CLI（`hs.ipc`）と各モジュールを読み込む |
| `chrome_translate.lua` | Chrome 標準のページ翻訳を「原文 ⇔ 日本語」で切り替える |

## セットアップ

1. `brew install --cask hammerspoon`
2. このリポジトリを `~/.hammerspoon` に clone する
3. 「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で Hammerspoon をオンにし、Hammerspoon を再起動する

## chrome_translate

拡張機能を使わず、アドレスバーの翻訳アイコンと翻訳バブルの言語タブをアクセシビリティ API で押す。

| キー | 動作 |
|---|---|
| ⌃⌥T | 原文 ⇔ 日本語 を切り替える |
| ⌃⌥⇧T | Chrome のボタン類の AX 情報をコンソールに出力する（診断用） |

- ホットキーは Chrome が前面のときだけ有効で、他のアプリのキー入力は奪わない
- 翻訳アイコンが出ていないページ（日本語のページなど）では、アラートを出すだけで終わる
- Chrome の UI 構造（翻訳アイコンの読み上げ名「翻訳」、バブル内の言語タブ）に依存する。Chrome の更新で動かなくなったら ⌃⌥⇧T の出力で構造を確かめる
