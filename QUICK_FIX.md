# 🚀 Quick Fix - Odin Not Found

## Problem

```
❌ Error: Odin not found in PATH
```

## Solution

Odinバイナリはインストール済みですが、PATHに追加されていません。

### Option 1: 手動でPATHを設定

```bash
# Odinがどこにあるか確認
ls ~/opt/odin/odin
ls ~/odin/odin
ls ~/Odin/odin

# 見つかったら、そのディレクトリをPATHに追加
# 例: ~/opt/odin/odin が見つかった場合
export PATH=$HOME/opt/odin:$PATH

# 確認
odin version

# ビルド
cd ~/AmeFileManger
./build.sh
```

### Option 2: 自動検索スクリプトを使用

```bash
cd ~/AmeFileManger
./setup_path.sh
```

このスクリプトがOdinを自動で探して、設定方法を教えてくれます。

### Option 3: 直接確認

```bash
# Odinバイナリを探す
find ~ -name "odin" -type f 2>/dev/null

# 見つかったパスをメモして
# 例: /home/tatsuya/opt/odin/odin なら

export PATH=/home/tatsuya/opt/odin:$PATH

# テスト
odin version
cd ~/AmeFileManger
./build.sh
```

## 永続的な設定

一時的な設定は端末を閉じると消えます。永続化するには：

```bash
# シェル設定ファイルを編集
nano ~/.profile

# または
nano ~/.config/sh/profile

# 以下を追加（パスは実際の場所に変更）
export PATH=$HOME/opt/odin:$PATH
export PATH=$HOME/opt/zig:$PATH

# 保存して再読み込み
source ~/.profile
```

## Zigも同様に

Zigも見つからない場合は同じ手順で：

```bash
export PATH=$HOME/opt/zig:$PATH
```

## 確認

全て設定したら：

```bash
odin version
zig version
cd ~/AmeFileManger
./build.sh
```

これで動くはずです！ 🎉
