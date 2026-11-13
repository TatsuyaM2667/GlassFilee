# Ame-FileManager

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
- **サムネイル**: 写真・動画（ffmpeg で生成、GNOME と共通のキャッシュ、画面に見えている分だけ）。
- **2画面表示**（F3、Tab で切り替え）。
- **目に見えるドラッグ＆ドロップ**: ドラッグしたファイルはカードの束になって浮き上がり（個数バッジ付き）、
  カーソルにふわっと付いてきます。フォルダー・サイドバーの場所・USB・ゴミ箱・タグが置き先として光り、
  「移動 → 仕事」のように何が起きるかを表示（Ctrl でコピー、Shift で移動）。フォルダーやタブの上で
  少し待つと開き、一覧の端では自動でスクロール。置くとカードが吸い込まれます。画面間や他のアプリとも使えます。
- **裏で動くコピー・移動**: 進捗パネルとキャンセル。**元に戻す**（Ctrl+Z か通知の「元に戻す」）は
  ゴミ箱・名前変更・移動・コピー・新しいフォルダーに対応。
- **自動更新**: 他のアプリが変えたファイルもすぐ反映（inotify / kqueue）。
- **フォルダーの自動変換**（Filee の watch）: フォルダーの空き部分を右クリック→「自動変換を設定…」で、
  入ってきたファイルを自動で変換。
- **ドーナツの裏面**: 変換ドーナツで Tab（またはホイール）を押すと裏返り、回転・左右反転・白黒・縮小・
  正方形切り抜き・音声削除・音量を整える・ZIP にまとめる などが使えます。リングは ffmpeg の実際の進み具合を表示。
- **音楽プレイヤー**: 曲をクリックするとすぐ再生され、Apple Music 風のバーが下に出ます。サブフォルダーの曲も
  まとめて再生（フォルダーを右クリック→「音楽を再生」）。全画面の再生画面では、同じ名前の `.lrc` で歌詞が
  同期表示され、同じ名前の `.mp4` は MV として流れます。ジャケット画像入りの曲はアイコンにジャケットが出ます。
- **すべてのファイルのビューアー**: 画像（拡大・移動）、PDF（ページ送り）、動画、SVG、テキスト・コード、
  Office / EPUB の本文、圧縮ファイルの中身一覧、フォントの見本、それ以外は 16 進ダンプ。
- **並べ替えとグループ**: 名前・更新日時・作成日時・アクセス日時・サイズ・種類・拡張子・タグの 8 通り、
  昇順／降順、フォルダー優先、見出し付きのグループ（種類・日付・サイズ・拡張子・タグ・頭文字）。
  並べ方はフォルダーごとに記憶します。
- **言語・フレームワークのアイコン**: ソースファイルには言語のロゴ（Python・Rust・TypeScript・Go・Odin など）、
  PDF には Acrobat のロゴ、プロジェクトのフォルダーには package.json や Cargo.toml から判定したフレームワークのバッジ
  （React・Next.js・Vue・Svelte・Angular・Yew・Leptos・Dioxus・Tauri・Django・Flutter・Rails・Laravel など）。
  本物のロゴ約 80 個（主に [Simple Icons](https://simpleicons.org)、出典は `assets/icons/SOURCES.md`）を
  アプリに埋め込み、Odin で書いた小さな SVG 描画エンジンで描いています。
- **iPad のようなタグ**: 名前と色を自由に作れます。タグを付けたフォルダーはその色になります。
- **ツリー表示**（Ctrl+3）: Obsidian 風。アイコン表示・一覧表示と切り替え。
- **パスをコピー**（右クリック、または Shift+Ctrl+C）。パスバーの文字もコピー＆ペーストできます。
- **ブックマーク**（GNOME と共通）、**USB ドライブ**（udisks2 でマウント／取り出し）、**Git の状態**表示、**プロパティ**（Ctrl+I）、**まとめて名前変更**
  （複数選択して F2。`*` = 元の名前、`##` = 番号）。
- **ドーナツ型の右クリックメニュー**: 変換ドーナツと同じく渦を巻いて開きます。色ラベルはリングの下の弧に並びます。
- **なめらかなアニメーション**（スクロール、フォルダーを開いた時の連続表示、メニュー、ダイアログ、通知）。
  動いている間だけ描画するので軽いままです。

## インストール

```bash
git clone https://github.com/TatsuyaM2667/ame-Filemanager.git
cd ame-Filemanager
./install.sh                # → ~/.local/bin/ame-filemanager、ランチャー登録、既定のファイルマネージャーに設定
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

背景の不透明度: `GF_OPACITY=0.85 ame-filemanager`（既定 0.7）。

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
| F3 / Tab | 2画面表示 / 画面の切り替え |
| Ctrl+Z | 元に戻す |
| Ctrl+D / Ctrl+I | ブックマークに追加 / プロパティ |
| Ctrl+1 / Ctrl+2 / Ctrl+3 | 一覧表示 / アイコン表示 / ツリー表示 |
| Shift+Ctrl+C | パスをコピー |
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
