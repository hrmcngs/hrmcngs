#!/usr/bin/env bash
# ============================================================================
# GitHub Stats Charts — ワンライナー セットアップ
# ----------------------------------------------------------------------------
# 任意の GitHub リポジトリの Codespaces/ターミナルで貼り付けて実行する:
#
#   curl -fsSL https://raw.githubusercontent.com/hrmcngs/hrmcngs/main/bootstrap.sh | bash
#
# 動作:
#   1. git remote (origin) から GitHub ユーザー名を自動検出
#      （GHS_USER=foo で上書き可）
#   2. scripts/gen-charts.js / src/js/charts.js / .github/workflows/update-charts.yml
#      を hrmcngs リポジトリから取得
#   3. CONFIG.user を検出した名前に書き換え
#   4. その場で 1 回 SVG を生成して charts/ に出力
#   5. 以降は GitHub Actions が 12 時間ごとに自動更新
# ============================================================================

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/hrmcngs/hrmcngs/main"

# --- 実行場所のチェック ----------------------------------------------------
if [ ! -d .git ]; then
  echo "[err] git リポジトリ内で実行してください（.git が見つかりません）。" >&2
  echo "      'git init' 済みのディレクトリで実行してください。" >&2
  exit 1
fi

# --- ユーザー名検出 --------------------------------------------------------
GHS_USER="${GHS_USER:-}"
if [ -z "$GHS_USER" ]; then
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  # https://github.com/OWNER/repo(.git) または git@github.com:OWNER/repo(.git) から OWNER 抽出
  GHS_USER="$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')"
fi
if [ -z "$GHS_USER" ]; then
  echo "[err] GitHub ユーザー名を検出できませんでした。" >&2
  echo "      GHS_USER=your-name を指定して再実行してください。" >&2
  exit 1
fi
echo "[*] ユーザー: $GHS_USER"

# --- ファイル取得 ----------------------------------------------------------
mkdir -p scripts src/js .github/workflows charts
echo "[*] ファイル取得中…"
curl -fsSL "$REPO_RAW/scripts/gen-charts.js"             -o scripts/gen-charts.js
curl -fsSL "$REPO_RAW/src/js/charts.js"                  -o src/js/charts.js
curl -fsSL "$REPO_RAW/.github/workflows/update-charts.yml" -o .github/workflows/update-charts.yml
touch charts/.gitkeep

# --- CONFIG.user を検出したユーザーに置換 ---------------------------------
# 先頭の `user: '...',` 行だけを書き換える（GitHub ユーザー名は英数字とハイフンのみ）
sed -i.bak -E "s/(user: ')[^']*(',)/\1${GHS_USER}\2/" scripts/gen-charts.js
rm -f scripts/gen-charts.js.bak
echo "[*] scripts/gen-charts.js の CONFIG.user を '$GHS_USER' に設定"

# --- 1 回生成 --------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  ver="$(node -e 'process.stdout.write(process.versions.node.split(".")[0])')"
  if [ "$ver" -ge 20 ]; then
    echo "[*] チャート生成中…"
    node scripts/gen-charts.js
  else
    echo "[!] Node $ver 検出 — gen-charts.js は Node 20+ が必要です。生成はスキップ。"
  fi
else
  echo "[!] node コマンドが見つかりません。'node scripts/gen-charts.js' を手動で実行してください。"
fi

# --- 完了案内 --------------------------------------------------------------
cat <<EOF

[✓] セットアップ完了。

次の手順:
  git add scripts src .github charts
  git commit -m "feat: add github-stats-charts"
  git push

README.md に画像として埋め込む:
  ![activity](charts/activity.svg)
  ![languages](charts/languages.svg)
  ![contributions](charts/contributions.svg)

以降は .github/workflows/update-charts.yml が 12 時間ごとに自動更新します。
EOF
