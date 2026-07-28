#!/usr/bin/env bash
#
# ================================================================
# 画像・ファイル整理ツール
# ================================================================
#
# 【対応環境】
# - VS CodeのWSLターミナル（Ubuntuなど）
# - 通常のWSLターミナル
# - LinuxのBashターミナル
#
# ※ WindowsのPowerShellだけでは直接動きません。
#    VS Code左下に「WSL: Ubuntu」などと表示された状態、または
#    VS Codeのターミナルで `wsl` と入力してから使用してください。
#
#
# 【初回だけ必要な準備】
# VS CodeのWSLターミナルで以下を実行します。
#
#   sudo apt update
#   sudo apt install -y imagemagick libheif1
#
# HEICを変換できない場合は、追加で以下を実行してください。
#
#   sudo apt install -y libheif-examples
#
#
# 【VS Codeのターミナルで起動する方法】
# このファイルを整理したい画像フォルダーへ入れ、VS Codeでその
# フォルダーを開きます。その後「ターミナル」→「新しいターミナル」
# を選び、以下を実行してください。
#
#   bash ./image-file-tool.sh
#
# `bash`を付ける方法なら、chmodによる実行権限の設定は不要です。
#
# 実行ファイルとして直接起動したい場合は、初回だけ以下を実行します。
#
#   chmod +x image-file-tool.sh
#   ./image-file-tool.sh
#
#
# 【Windows側のフォルダーへ移動する例】
# C:\Users\名前\Pictures は、WSLでは次の場所になります。
#
#   cd "/mnt/c/Users/名前/Pictures"
#   bash ./image-file-tool.sh
#
#
# 【機能】
# 1. 指定した拡張子のファイルを削除
#    - 拡張子は `nef` または `.nef` のように入力できます。
#    - 大文字と小文字は区別しません。
#    - サブフォルダーを対象にするか選択できます。
#    - 候補を一覧表示し、DELETEと入力した場合だけ削除します。
#
# 2. HEIC/HEIFまたはPNGをJPGに変換
#    - JPEG品質を1～100で指定できます（初期値は92）。
#    - 変換元の画像は削除しません。
#    - 同じ名前のJPGがある場合は上書きせずスキップします。
#    - PNGの透明部分は白背景に変換します。
#
#
# 【対象フォルダーについて】
# 「このプログラムがある上記フォルダーを使いますか？」で、そのまま
# Enterを押すと、image-file-tool.shを置いたフォルダーが選択されます。
#
# ファイル名やフォルダー名に空白・日本語が含まれていても使用できます。
# ================================================================

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

pause() {
  printf '\nEnterキーでメニューに戻ります...'
  read -r _
}

ask_directory() {
  local use_current input
  printf '\n対象フォルダー:\n'
  printf '  %s\n' "$SCRIPT_DIR"
  printf 'このプログラムがある上記フォルダーを使いますか？ [Y/n]\n> '
  read -r use_current

  if [[ -z "$use_current" || "$use_current" =~ ^[Yy]$ ]]; then
    input="$SCRIPT_DIR"
  else
    printf '別の対象フォルダーをフルパスで入力してください。\n'
    printf '例: /mnt/c/Users/名前/Pictures\n> '
    read -r input
  fi

  if [[ -z "$input" || ! -d "$input" ]]; then
    printf 'エラー: フォルダーが見つかりません: %s\n' "$input" >&2
    return 1
  fi

  TARGET_DIR="$(cd -- "$input" && pwd)"
}

delete_by_extension() {
  local extension recursive answer
  local -a files=()

  printf '\n削除する拡張子を入力してください。\n'
  printf '例: nef または .nef\n> '
  read -r extension
  extension="${extension#.}"

  if [[ -z "$extension" || "$extension" == */* || "$extension" == *\\* ]]; then
    printf 'エラー: 拡張子を正しく入力してください。\n' >&2
    return
  fi

  ask_directory || return

  printf 'サブフォルダー内も対象にしますか？ [y/N]\n> '
  read -r recursive

  if [[ "$recursive" =~ ^[Yy]$ ]]; then
    while IFS= read -r -d '' file; do files+=("$file"); done \
      < <(find "$TARGET_DIR" -type f -iname "*.${extension}" -print0)
  else
    while IFS= read -r -d '' file; do files+=("$file"); done \
      < <(find "$TARGET_DIR" -maxdepth 1 -type f -iname "*.${extension}" -print0)
  fi

  if ((${#files[@]} == 0)); then
    printf '対象ファイルはありません。\n'
    return
  fi

  printf '\n削除候補 (%d件):\n' "${#files[@]}"
  printf '  %s\n' "${files[@]}"
  printf '\n本当に削除しますか？ 元に戻せません。削除するには DELETE と入力してください。\n> '
  read -r answer
  if [[ "$answer" != "DELETE" ]]; then
    printf 'キャンセルしました。\n'
    return
  fi

  local deleted=0 file
  for file in "${files[@]}"; do
    if rm -- "$file"; then
      ((deleted += 1))
    else
      printf '削除失敗: %s\n' "$file" >&2
    fi
  done
  printf '%d件を削除しました。\n' "$deleted"
}

find_converter() {
  if command -v magick >/dev/null 2>&1; then
    CONVERTER="magick"
  elif command -v convert >/dev/null 2>&1; then
    CONVERTER="convert"
  else
    CONVERTER=""
  fi
}

convert_images() {
  local source_type extension recursive quality answer file output
  local -a files=()

  ask_directory || return
  printf '変換元を選択してください。\n  1) HEIC / HEIF → JPG\n  2) PNG → JPG\n> '
  read -r source_type
  case "$source_type" in
    1) extension="heic";;
    2) extension="png";;
    *) printf '選択が正しくありません。\n'; return;;
  esac

  printf 'JPEG品質（1～100、空欄は 92）\n> '
  read -r quality
  quality="${quality:-92}"
  if [[ ! "$quality" =~ ^[0-9]+$ ]] || ((quality < 1 || quality > 100)); then
    printf 'エラー: 品質は1～100で入力してください。\n' >&2
    return
  fi

  printf 'サブフォルダー内も対象にしますか？ [y/N]\n> '
  read -r recursive
  if [[ "$recursive" =~ ^[Yy]$ ]]; then
    if [[ "$source_type" == 1 ]]; then
      while IFS= read -r -d '' file; do files+=("$file"); done \
        < <(find "$TARGET_DIR" -type f \( -iname '*.heic' -o -iname '*.heif' \) -print0)
    else
      while IFS= read -r -d '' file; do files+=("$file"); done \
        < <(find "$TARGET_DIR" -type f -iname '*.png' -print0)
    fi
  else
    if [[ "$source_type" == 1 ]]; then
      while IFS= read -r -d '' file; do files+=("$file"); done \
        < <(find "$TARGET_DIR" -maxdepth 1 -type f \( -iname '*.heic' -o -iname '*.heif' \) -print0)
    else
      while IFS= read -r -d '' file; do files+=("$file"); done \
        < <(find "$TARGET_DIR" -maxdepth 1 -type f -iname '*.png' -print0)
    fi
  fi

  if ((${#files[@]} == 0)); then
    printf '変換対象はありません。\n'
    return
  fi

  find_converter
  if [[ -z "$CONVERTER" ]]; then
    printf 'ImageMagickが必要です。WSLで次を実行してください:\n'
    printf '  sudo apt update && sudo apt install -y imagemagick libheif1\n'
    return
  fi

  printf '\n変換対象: %d件（元ファイルは残します）\n' "${#files[@]}"
  printf '開始しますか？ [y/N]\n> '
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]] || { printf 'キャンセルしました。\n'; return; }

  local converted=0 skipped=0 failed=0
  for file in "${files[@]}"; do
    output="${file%.*}.jpg"
    if [[ -e "$output" ]]; then
      printf 'スキップ（変換先あり）: %s\n' "$output"
      ((skipped += 1))
      continue
    fi
    if "$CONVERTER" "$file" -background white -alpha remove -alpha off -quality "$quality" "$output"; then
      printf '変換: %s\n' "$output"
      ((converted += 1))
    else
      printf '変換失敗: %s\n' "$file" >&2
      [[ -e "$output" ]] && rm -- "$output"
      ((failed += 1))
    fi
  done
  printf '\n完了: 変換 %d / スキップ %d / 失敗 %d\n' "$converted" "$skipped" "$failed"
}

while true; do
  clear 2>/dev/null || true
  printf '=== 画像・ファイル整理ツール (WSL) ===\n'
  printf '  1) 指定した拡張子のファイルを削除\n'
  printf '  2) HEIC/HEIF または PNG を JPG に変換\n'
  printf '  0) 終了\n'
  printf '> '
  read -r choice || exit 0
  case "$choice" in
    1) delete_by_extension; pause;;
    2) convert_images; pause;;
    0) printf '終了します。\n'; exit 0;;
    *) printf '選択が正しくありません。\n'; pause;;
  esac
done
