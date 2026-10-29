#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CATALOG="$ROOT/_packages.tsv"
STATE="$ROOT/_state.tsv"
REPOS="$ROOT/repos.tsv"
PACKAGES="$ROOT/packages"
BIN="$PACKAGES/bin"
BOX_WIDTH=100

fail() { printf 'Error: %s\n' "$*" >&2; return 1; }
initialize_state() {
  [ -f "$STATE" ] || printf 'PACKAGE\tDATE\tVERSION\tSIZE_KB\tFILES\n' > "$STATE"
}
catalog_row() { awk -F '\t' -v name="$1" 'NR > 1 && $1 == name { print; exit }' "$CATALOG"; }
installed_version() { awk -F '\t' -v name="$1" 'NR > 1 && $1 == name { print $3; exit }' "$STATE"; }
repo_row() { awk -F '\t' -v name="$1" 'NR > 1 && $1 == name { print; exit }' "$REPOS"; }
repo_names() { awk -F '\t' 'NR > 1 && $1 != "" { print $1 }' "$REPOS"; }
repo_path() { repo_row "$1" | awk -F '\t' '{ print $4 }'; }
box_top() { printf '+'; printf '%*s' "$BOX_WIDTH" '' | tr ' ' '-'; printf '+\n'; }
box_bottom() { box_top; }
line() { printf '+'; printf '%*s' "$BOX_WIDTH" '' | tr ' ' '-'; printf '+\n'; }

add_to_path() {
  mkdir -p "$BIN"
  case ":$PATH:" in *":$BIN:"*) return ;; esac
  export PATH="$BIN:$PATH"
  profile="$HOME/.profile"; [ -f "$HOME/.zshrc" ] && profile="$HOME/.zshrc"
  marker='# parcel package bin'
  grep -F "$marker" "$profile" >/dev/null 2>&1 || {
    printf '\n%s\nexport PATH="%s:$PATH"\n' "$marker" "$BIN" >> "$profile"
    printf 'Added %s to PATH in %s.\n' "$BIN" "$profile"
  }
}

# Package operations -------------------------------------------------------
release() {
  package=$1; row=$(catalog_row "$package")
  [ -n "$row" ] || { fail "unknown package: $package"; return 1; }
  repo=$(printf '%s' "$row" | awk -F '\t' '{ sub("https://github.com/", "", $2); print $2 }')
  asset_match=$(printf '%s' "$row" | awk -F '\t' '{ print $3 }')
  binaries=$(printf '%s' "$row" | awk -F '\t' '{ print $4 }')
  json=$(mktemp "${TMPDIR:-/tmp}/parcel.XXXXXX")
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" -o "$json" || {
    rm -f "$json"; fail "could not read GitHub release for $package"; return 1;
  }
  version=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | head -n 1)
  case "$(uname -s)" in Darwin) os='apple|darwin|macos' ;; Linux) os='linux|unknown' ;; *) os=$(uname -s) ;; esac
  case "$(uname -m)" in arm64|aarch64) arch='aarch64|arm64' ;; x86_64|amd64) arch='x86_64|amd64|64' ;; *) arch=$(uname -m) ;; esac
  urls=$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | grep -vi '\.from-' || true)
  asset_match=$(printf '%s' "$asset_match" | sed "s/VERSION/${version#v}/g")
  asset_url=$(printf '%s\n' "$urls" | grep -Ei "$asset_match" | grep -Ei "$os" | grep -E "$arch" | head -n 1 || true)
  [ -n "$asset_url" ] || asset_url=$(printf '%s\n' "$urls" | grep -Ei "/$package-" | grep -Ev '\.(sha256|sum)$' | grep -Ei "$os" | grep -E "$arch" | head -n 1 || true)
  rm -f "$json"
  [ -n "$asset_url" ] || { fail "no matching release asset for $package"; return 1; }
}

save_state() {
  temp="$STATE.tmp.$$"
  awk -F '\t' -v name="$1" 'BEGIN { OFS="\t" } NR == 1 { print "PACKAGE", "DATE", "VERSION", "SIZE_KB", "FILES"; next } $1 != name { print }' "$STATE" > "$temp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(date -u +%F)" "$2" "$3" "$4" >> "$temp"
  mv "$temp" "$STATE"
}

link_binaries() {
  old_ifs=$IFS; IFS=,
  for binary in $binaries; do
    binary=${binary#/}; [ -n "$binary" ] || continue
    candidate=$(find "$destination" -type f -name "$binary" -print | head -n 1)
    [ -n "$candidate" ] || candidate=$(find "$destination" -type f -name "$binary-*" -print | head -n 1)
    if [ -n "$candidate" ] && [ "${candidate##*/}" != "$binary" ]; then
      mv "$candidate" "$(dirname "$candidate")/$binary"; candidate="$(dirname "$candidate")/$binary"
    fi
    [ -n "$candidate" ] || { printf 'Warning: %s was not found in %s.\n' "$binary" "$package" >&2; continue; }
    chmod u+x "$candidate"; ln -sf "$candidate" "$BIN/$binary"
  done
  IFS=$old_ifs
}

package_install() {
  release "$1" || return 1
  stage=$(mktemp -d "${TMPDIR:-/tmp}/parcel.XXXXXX"); unpacked="$stage/unpacked"
  file=${asset_url##*/}; destination="$PACKAGES/$package"
  printf 'Installing %s %s...\n' "$package" "$version"
  curl -fsSL "$asset_url" -o "$stage/$file" || { rm -rf "$stage"; fail 'download failed'; return 1; }
  mkdir "$unpacked"
  case "$file" in *.zip) unzip -q "$stage/$file" -d "$unpacked" ;; *.tar.xz|*.tar.gz|*.tgz) tar -xf "$stage/$file" -C "$unpacked" ;; *.gz) gzip -cd "$stage/$file" > "$unpacked/${file%.gz}" ;; *) cp "$stage/$file" "$unpacked" ;; esac
  rm -rf "$destination"; set -- "$unpacked"/*
  if [ $# -eq 1 ] && [ -d "$1" ]; then mv "$1" "$destination"; else mkdir -p "$destination"; mv "$unpacked"/* "$destination"; fi
  mkdir -p "$BIN"; link_binaries
  size_kb=$(du -sk "$destination" | awk '{ print $1 }'); file_count=$(find "$destination" -type f | wc -l | tr -d ' ')
  save_state "$package" "$version" "$size_kb" "$file_count"; rm -rf "$stage"
  printf 'Installed %s %s.\n' "$package" "$version"
}

package_remove() {
  [ -e "$PACKAGES/$1" ] || { fail "$1 is not installed"; return 1; }
  row=$(catalog_row "$1"); binaries=$(printf '%s' "$row" | awk -F '\t' '{ print $4 }')
  old_ifs=$IFS; IFS=,; for binary in $binaries; do binary=${binary#/}; [ -n "$binary" ] && rm -f "$BIN/$binary"; done; IFS=$old_ifs
  rm -rf "$PACKAGES/$1"
  awk -F '\t' -v name="$1" 'BEGIN { OFS="\t" } NR == 1 || $1 != name { print }' "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"
  printf 'Removed %s.\n' "$1"
}

package_update() {
  old=$(installed_version "$1"); release "$1" || return 1
  [ "$old" = "$version" ] && { printf '%s is already %s.\n' "$package" "$version"; return; }
  package_install "$package"
}
package_remove_all() { rm -rf "$PACKAGES"; mkdir -p "$BIN"; printf 'PACKAGE\tDATE\tVERSION\tSIZE_KB\tFILES\n' > "$STATE"; }
package_update_all() { awk -F '\t' 'NR > 1 { print $1 }' "$STATE" | while IFS= read -r name; do [ -n "$name" ] && package_update "$name"; done; }
package_list() { awk -F '\t' 'NR == 1 { next } { printf "%-18s %-14s %s\n", $1, $3, $2 }' "$STATE"; }

# Repository operations ----------------------------------------------------
require_repo() {
  path=$(repo_path "$1"); [ -n "$path" ] || { fail "unknown repository: $1"; return 1; }
  case "$path" in \~/*) path=$HOME/${path#\~/} ;; esac
  path=${path%/}; [ -d "$path/.git" ] || { fail "$1 is not a Git repository at $path"; return 1; }
}
repo_loc() { find "$1" -type f ! -path '*/.git/*' -exec wc -l {} + 2>/dev/null | awk 'END { print $1 + 0 }'; }
repo_sync() {
  name=$1; local_url=$(repo_path "$name"); require_repo "$name" || return 1
  remote=$(git -C "$path" remote get-url origin 2>/dev/null || true)
  branches=$(git -C "$path" for-each-ref --format='%(refname:short)' refs/heads | paste -sd, -)
  size_kb=$(du -sk "$path" | awk '{ print $1 }'); files=$(find "$path" -type f ! -path '*/.git/*' | wc -l | tr -d ' ')
  loc=$(repo_loc "$path"); commit_date=$(git -C "$path" log -1 --format=%cs 2>/dev/null || true)
  message=$(git -C "$path" log -1 --format=%s 2>/dev/null | tr '\t\n' ' ' || true); temp="$REPOS.tmp.$$"
  awk -F '\t' -v name="$name" -v remote="$remote" -v branches="$branches" -v path="$local_url" -v size="$size_kb" -v files="$files" -v loc="$loc" -v date="$commit_date" -v message="$message" 'BEGIN { OFS="\t" } NR == 1 { print; next } $1 == name { print $1, remote, branches, path, size, files, loc, date, message; next } { print }' "$REPOS" > "$temp"
  mv "$temp" "$REPOS"
}
repo_sync_all() { repo_names | while IFS= read -r name; do repo_sync "$name" || true; done; }
repo_pull() { require_repo "$1" || return 1; branch=$(git -C "$path" branch --show-current); [ -n "$branch" ] || { fail "$1 is in detached HEAD state"; return 1; }; git -C "$path" pull --ff-only origin "$branch"; repo_sync "$1"; }
repo_commit() { require_repo "$1" || return 1; [ -n "$2" ] || { fail 'a commit message is required'; return 1; }; git -C "$path" commit -m "$2"; repo_sync "$1"; }
repo_push() { require_repo "$1" || return 1; branch=$(git -C "$path" branch --show-current); [ -n "$branch" ] || { fail "$1 is in detached HEAD state"; return 1; }; git -C "$path" add -A; git -C "$path" commit -m "$2"; git -C "$path" push origin "$branch"; repo_sync "$1"; }
repo_rollback() { require_repo "$1" || return 1; git -C "$path" rev-parse --verify HEAD~1 >/dev/null || { fail "$1 has no commit to roll back"; return 1; }; git -C "$path" reset --hard HEAD~1; git -C "$path" clean -fd; repo_sync "$1"; }
repo_list() { awk -F '\t' 'NR > 1 { printf "%-18s %-14s %-10s %s\n", $1, $3, $8, $9 }' "$REPOS"; }

# Combined TUI -------------------------------------------------------------
tui_size() { awk -v kb="${1:-}" 'BEGIN { if (kb == "") print ""; else if (kb >= 1048576) printf "%.1fG", kb / 1048576; else if (kb >= 1024) printf "%.1fM", kb / 1024; else printf "%sK", kb }'; }
tui_title() {
  box_top
  if [ "$tab" = tools ]; then tabs='[ TOOLS ]   REPOS'; keys='arrows move/switch | space select | + install | ^ update | - remove | q quit'
  else tabs='  TOOLS   [ REPOS ]'; keys='arrows move/switch | space select | < pull | > push | + commit | - rollback | q quit'; fi
  printf '| %-24s %-73.73s |\n' "$tabs" "$keys"; line
}
tui_selected() { case ",$selected," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
tui_toggle() { if tui_selected "$1"; then selected=$(printf '%s' ",$selected," | sed "s/,$1,/,/; s/^,//; s/,$//"); else selected=${selected:+"$selected,"}$1; fi; }
tui_current() { awk -F "$sep" -v row="$cursor" 'NR == row { print $1; exit }' "$rows"; }
tui_select_all() { selected=$(awk -F "$sep" '{ printf "%s%s", separator, $1; separator="," }' "$rows"); }
tui_load() {
  if [ "$tab" = tools ]; then
    rows="$cache/tools"; awk -F '\t' -v s="$sep" 'NR == FNR { if (FNR > 1) { v[$1]=$3; z[$1]=$4; f[$1]=$5 }; next } FNR > 1 { print $1 s $4 s v[$1] s z[$1] s f[$1] }' "$STATE" "$CATALOG" > "$rows"
    cursor=$tools_cursor; selected=$tools_selected
  else
    rows="$cache/repos"; awk -F '\t' -v s="$sep" 'NR > 1 { print $1 s $3 s $5 s $6 s $7 s $8 s $9 }' "$REPOS" > "$rows"
    cursor=$repos_cursor; selected=$repos_selected
  fi
  total=$(awk 'END { print NR }' "$rows"); [ "$total" -gt 0 ] || cursor=0; [ "$cursor" -le "$total" ] || cursor=$total
}
tui_save_tab() { if [ "$tab" = tools ]; then tools_cursor=$cursor; tools_selected=$selected; else repos_cursor=$cursor; repos_selected=$selected; fi; }
tui_switch() { tui_save_tab; if [ "$tab" = tools ]; then tab=repos; else tab=tools; fi; status=''; tui_load; }
tui_render() {
  printf '\033[H'; tui_title; index=0
  if [ "$tab" = tools ]; then
    while IFS="$sep" read -r name binaries version size_kb files; do
      index=$((index + 1)); tui_selected "$name" && mark=x || mark=' '; [ "$index" -eq "$cursor" ] && pointer='>' || pointer=' '
      size=$(tui_size "$size_kb"); binaries=$(printf '%s' "$binaries" | tr -d '/')
      printf '| %s[%s] %-18.18s %-14.14s %7s %7s %-43.43s |\n' "$pointer" "$mark" "$name" "$version" "$size" "$files" "$binaries"
    done < "$rows"
  else
    while IFS="$sep" read -r name branches size files loc commit_date message; do
      index=$((index + 1)); tui_selected "$name" && mark=x || mark=' '; [ "$index" -eq "$cursor" ] && pointer='>' || pointer=' '; size=$(tui_size "$size")
      printf '| %s[%s] %-18.18s %-12.12s %7s %7s %9s %-10.10s %-24.24s |\n' "$pointer" "$mark" "$name" "$branches" "$size" "$files" "$loc" "$commit_date" "$message"
    done < "$rows"
  fi
  line; printf '| %-98.98s |\n' "$status"; box_bottom; printf '\033[J'
}
tui_action() {
  action=$1; [ -n "$selected" ] || { status='Select at least one item first.'; return; }
  message=''
  case "$action" in repo_push|repo_commit) printf '\033[?25h\nCommit message: '; read -r message; printf '\033[?25l'; [ -n "$message" ] || { status='Cancelled: no message.'; return; } ;; esac
  case "$action" in repo_rollback) printf '\033[?25h\nType ROLLBACK to discard each selected repository latest commit and local changes: '; read -r answer; printf '\033[?25l'; [ "$answer" = ROLLBACK ] || { status='Rollback cancelled.'; return; } ;; esac
  output="$cache/output"; : > "$output"; completed=''; old_ifs=$IFS; IFS=,
  for name in $selected; do
    case "$action" in
      package_install) if [ -n "$(installed_version "$name")" ]; then package_update "$name"; else package_install "$name"; fi >> "$output" 2>&1 ;; package_update) if [ -n "$(installed_version "$name")" ]; then package_update "$name"; else fail "$name is not installed"; fi >> "$output" 2>&1 ;; package_remove) package_remove "$name" >> "$output" 2>&1 ;;
      repo_pull) repo_pull "$name" >> "$output" 2>&1 ;; repo_push) repo_push "$name" "$message" >> "$output" 2>&1 ;; repo_commit) repo_commit "$name" "$message" >> "$output" 2>&1 ;; repo_rollback) repo_rollback "$name" >> "$output" 2>&1 ;;
    esac && completed=${completed:+"$completed, "}$name || status="Failed: $name - $(tail -n 1 "$output" | tr '\t\n' ' ')"
  done
  IFS=$old_ifs; [ -n "$status" ] || status="Done: $completed"; selected=''; tui_save_tab; tui_load
}
tui() {
  [ -t 0 ] && [ -t 1 ] || { package_list; return; }
  saved_tty=$(stty -g); cache=$(mktemp -d "${TMPDIR:-/tmp}/parcel.XXXXXX"); sep=$(printf '\034')
  cleanup() { stty "$saved_tty" 2>/dev/null || true; rm -rf "$cache"; printf '\033[?25h\033[?1049l'; }
  trap cleanup EXIT HUP INT TERM; printf '\033[?1049h\033[?25l\033[H'
  tab=tools; tools_cursor=1; repos_cursor=1; tools_selected=''; repos_selected=''; status=''; tui_load
  while :; do
    tui_render; stty -echo -icanon time 0 min 1; key=$(dd bs=1 count=1 2>/dev/null)
    if [ "$key" = "$(printf '\033')" ]; then stty -echo -icanon time 1 min 0; sequence=$(dd bs=1 count=2 2>/dev/null); case "$sequence" in '[A'|OA) key=up ;; '[B'|OB) key=down ;; '[C'|OC) key=right ;; '[D'|OD) key=left ;; *) key='' ;; esac; fi
    stty "$saved_tty"; status=''
    case "$key" in
      up|k) [ "$cursor" -gt 1 ] && cursor=$((cursor - 1)) ;; down|j) [ "$cursor" -lt "$total" ] && cursor=$((cursor + 1)) ;; left|right) tui_switch ;;
      J) cursor=$((cursor + 10)); [ "$cursor" -gt "$total" ] && cursor=$total ;; K) cursor=$((cursor - 10)); [ "$cursor" -lt 1 ] && cursor=1 ;;
      ' ') [ "$total" -gt 0 ] && tui_toggle "$(tui_current)" ;; '*') tui_select_all ;;
      '+') if [ "$tab" = tools ]; then tui_action package_install; else tui_action repo_commit; fi ;; '^') [ "$tab" = tools ] && tui_action package_update ;; '-') if [ "$tab" = tools ]; then tui_action package_remove; else tui_action repo_rollback; fi ;; '<') [ "$tab" = repos ] && tui_action repo_pull ;; '>') [ "$tab" = repos ] && tui_action repo_push ;; q) break ;;
    esac
  done
  trap - EXIT HUP INT TERM; cleanup
}

usage() { fail 'Usage: parcel [catalog|list|install PKG...|remove PKG...|update [PKG...|all]|repos list|refresh [REPO...]|pull REPO...|push REPO... --message MSG|commit REPO... --message MSG|rollback REPO...]'; }
repo_cli() {
  [ $# -gt 0 ] || usage; command=$1; shift
  case "$command" in
    list) repo_list ;; refresh) if [ $# -eq 0 ]; then repo_sync_all; else for name in "$@"; do repo_sync "$name"; done; fi ;; pull) for name in "$@"; do repo_pull "$name"; done ;; rollback) for name in "$@"; do repo_rollback "$name"; done ;;
    push|commit) action=$command; message=''; names=''; while [ $# -gt 0 ]; do case "$1" in --message) shift; message=${1:-} ;; *) names="$names $1" ;; esac; shift || true; done; [ -n "$message" ] || usage; for name in $names; do "repo_$action" "$name" "$message"; done ;;
    *) usage ;;
  esac
}

initialize_state
[ -f "$REPOS" ] || printf 'REPOSITORY\tREMOTE_URL\tBRANCHES\tLOCAL_URL\tSIZE_KB\tFILES\tLOC\tDATE\tLAST_COMMIT\n' > "$REPOS"
add_to_path
[ $# -gt 0 ] || { tui; exit 0; }
case "$1" in
  tools) shift; [ $# -gt 0 ] || { tui; exit 0; } ;; repos) shift; repo_cli "$@"; exit $? ;;
esac
case "${1:-}" in
  catalog) cat "$CATALOG" ;; list) package_list ;; install) shift; [ $# -gt 0 ] || usage; for name in "$@"; do package_install "$name"; done ;; remove) shift; [ $# -gt 0 ] || usage; if [ "$1" = all ]; then package_remove_all; else for name in "$@"; do package_remove "$name"; done; fi ;; update) shift; if [ $# -eq 0 ] || [ "$1" = all ]; then package_update_all; else for name in "$@"; do package_update "$name"; done; fi ;; *) usage ;;
esac
