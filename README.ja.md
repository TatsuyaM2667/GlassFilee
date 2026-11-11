# GlassFilee

[English](README.md) | **日本語**

**Odin** だけで書いた、GNOME Files 風の半透明ファイルマネージャーです。Filee のような
「ドラッグで変換」を標準で内蔵しています。Wayland と直接やり取りするので GTK も SDL も GPU も使わず、
待機中は **CPU 0%・メモリ約 19MB** です。

## 機能

- **GNOME Files と同じ見た目**: サイドバー（ホーム・ドキュメント・ダウンロード・ピクチャ・ビデオ・ゴミ箱・コンピューター）、
  戻る/進む、パンくず式のパスバー、アイコン表示と一覧表示、並べ替え、ドラッグでの範囲選択、
  右クリックメニュー、名前の変更・新しいフォルダーのダイアログ。背景は ame-shell のターミナルと同じ透け具合。
- **ブラウザのような常時タブ**: `+` ボタン、Ctrl+T / Ctrl+W / Ctrl+Tab、フォルダーを中クリックで新しいタブ。
- **Filee 風の変換**: ファイルを Ctrl+ドラッグ（または右クリック→変換…、Ctrl+E）すると、
  カーソル位置に形式のドーナツメニューが渦を巻いて開きます。形式の上で離すと、元ファイルの隣に変換結果ができ、
  変換中はアイコンに進捗リングが回ります。入っているツールを自動で使います:
  ffmpeg（画像・動画・音声）、pandoc（文書）、LibreOffice（オフィス→PDF）、ImageMagick（画像→PDF）、bsdtar（圧縮ファイル）。
- **圧縮ファイル**: 右クリック→「ここに展開」で zip・tar.gz/xz/zst/bz2/lz4・7z・rar・iso・deb・rpm など（bsdtar）と、
  単体の .gz/.xz/.zst/.bz2/.lz4 を展開。「圧縮…」で .zip / .tar.gz / .tar.xz / .7z を作成。どちらも裏で動きます。
- **クイックプレビュー**（スペースキー）: 画像・動画の1コマ・テキストがアイコンから拡大表示。←/→ で前後へ。
- **検索**: 今のフォルダーを即座に絞り込み、裏でサブフォルダーまで探します。
- **ゴミ箱**（freedesktop 仕様で GNOME と共通）: 移動・元に戻す・空にする。
- **他のアプリとのコピー＆ペースト**（GNOME / KDE / ブラウザ）。
- **なめらかなアニメーション**（スクロール、フォルダーを開いた時の連続表示、メニュー、ダイアログ、通知）。
  動いている間だけ描画するので軽いままです。

## インストール

```bash
git clone https://github.com/TatsuyaM2667/ame-Filemanager.git
cd ame-Filemanager
./install.sh                # → ~/.local/bin/gf-gui、ランチャー登録、既定のファイルマネージャーに設定
NO_DEFAULT=1 ./install.sh   # 既定のファイルマネージャーは変えない
```

| システム | 手順 |
| --- | --- |
| Chimera Linux | Odin は odin-lang.org から入れて、`apk add wayland-devel libxkbcommon-devel freetype-devel libarchive-progs ffmpeg` → `./install.sh` |
| Arch Linux | `cd packaging/arch && makepkg -si` |
| FreeBSD | `pkg install odin wayland libxkbcommon freetype2 libarchive xdg-utils ffmpeg` → `./install.sh` |

必要なもの: xdg-shell 対応の Wayland コンポジター、新しい Odin（dev-2026-08 以降）、
libwayland、libxkbcommon、FreeType、bsdtar。フォントは Adwaita Sans・Noto Sans CJK・Symbols Nerd Font
（無い場合は `fc-match` で探します）。

背景の不透明度: `GF_OPACITY=0.85 gf-gui`（既定 0.7）。

## キー操作

| キー | 動作 |
| --- | --- |
| Enter / ダブルクリック | 開く |
| スペース | クイックプレビュー |
| Ctrl+ドラッグ / Ctrl+E | 変換（ドーナツメニュー） |
| Alt+← / Alt+→ / Alt+↑ | 戻る / 進む / 上へ |
| Ctrl+L / Ctrl+F | パス入力 / 検索（文字を打つだけでも検索） |
| Ctrl+C / Ctrl+X / Ctrl+V | コピー / 切り取り / 貼り付け |
| F2 | 名前の変更 |
| Delete / Shift+Delete | ゴミ箱へ移動 / 完全に削除 |
| Ctrl+Shift+N | 新しいフォルダー |
| Ctrl+T / Ctrl+W / Ctrl+Tab | 新しいタブ / タブを閉じる / 次のタブ |
| Ctrl+1 / Ctrl+2 | 一覧表示 / アイコン表示 |
| Ctrl+H | 隠しファイルの表示 |
| Ctrl+A、F5、Ctrl+Q | すべて選択、再読み込み、終了 |

## 構成

```
src/core/    Odin のコア: ファイル操作・ゴミ箱（CLI 用に C ABI のライブラリとしてもビルド）
src/gui/     Odin の GUI: Wayland クライアント (wl.odin)、描画 (draw.odin)、フォント (font.odin)、
             本体 (app.odin)、変換 (convert.odin)、プレビュー、圧縮ファイル
src/cli/     gf-cli: コアを使う小さな Zig 0.13 製コマンド（任意）
tests/       Odin のゴミ箱テスト。./test.sh で全テストを実行
```

## ライセンス

MIT
