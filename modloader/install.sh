#!/usr/bin/env bash
set -euo pipefail

# TMFLiveReplay Linux installer for TrackMania United Forever
# Installed through Lutris: https://lutris.net/games/install/38956/view
# TMLoader is expected at "Program Files/TMLoader" inside the game's Wine prefix.

SERVER_URL='https://raw.githubusercontent.com/AroPix/TMFLiveReplay/refs/heads/master/modloader/'
GAMEDIR="${1:-$HOME/Games/trackmania-united-forever}"
CONFIG_PATH="$GAMEDIR/drive_c/Program Files/TMLoader/config.yaml"

fail() {
    echo "error: $*" >&2
    exit 1
}

[ -f "$CONFIG_PATH" ] || fail "Config file not found at '$CONFIG_PATH'. Expected TMLoader at '$GAMEDIR/drive_c/Program Files/TMLoader' (installed via the Lutris script)."

config_has_url() {
    grep -Fq "$SERVER_URL" "$CONFIG_PATH"
}

if config_has_url; then
    echo "TMFLiveReplay is already installed in TMLoader."
    exit 0
fi

# Add the server under a 'servers:' key. If the key exists, append after its
# last list item; otherwise append the key at the end of the file.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

append_line() {
    cp "$CONFIG_PATH" "$tmp"
    printf '%s\n' "$1" >>"$tmp"
    mv "$tmp" "$CONFIG_PATH"
}

find_servers_line() {
    local n=0 line indent rest
    while IFS= read -r line; do
        n=$((n + 1))
        if [[ "$line" =~ ^([[:space:]]*)servers:[[:space:]]*(.*)$ ]]; then
            indent=${BASH_REMATCH[1]}
            rest=${BASH_REMATCH[2]}
            echo "$n|$indent|$rest"
            return 0
        fi
    done <"$CONFIG_PATH"
    return 1
}

servers_line="$(find_servers_line)" || servers_line=''

if [ -z "$servers_line" ]; then
    last_line="$(tail -n 1 "$CONFIG_PATH" 2>/dev/null || true)"
    if [ -n "$last_line" ] && [ -n "$(echo "$last_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" ]; then
        printf '\n' >>"$CONFIG_PATH"
    fi
    append_line 'servers:'
    append_line "  - $SERVER_URL"
else
    n="${servers_line%%|*}"
    rest="${servers_line##*|}"
    indent="${servers_line#*|}"
    indent="${indent%|*}"

    item_indent="  ${indent}"
    new_item="${item_indent}- $SERVER_URL"

    if [ "$rest" = '[]' ]; then
        awk -v target="$n" -v item="$new_item" '
            NR == target { sub(/servers:[[:space:]]*\[\]/, "servers:"); print; print item; next }
            { print }
        ' "$CONFIG_PATH" >"$tmp"
        mv "$tmp" "$CONFIG_PATH"
        echo "TMFLiveReplay installed! Reopen TMLoader so it gets fetched."
        exit 0
    fi

    awk -v target="$n" -v item="$new_item" -v min_len="${#indent}" '
        function leading_spaces(s,  i) {
            i = 0
            while (i < length(s) && (substr(s, i+1, 1) == " " || substr(s, i+1, 1) == "\t")) i++
            return i
        }
        NR == target { print; found = 1; next }
        found == 1 {
            if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) { print; next }
            if (leading_spaces($0) <= min_len && $0 ~ /^[[:space:]]*[^#-][^:]*:/) {
                print item
                found = 2
            }
            print
            next
        }
        { print }
        END { if (found == 1) print item }
    ' "$CONFIG_PATH" >"$tmp"
    mv "$tmp" "$CONFIG_PATH"

    if ! config_has_url; then
        echo "Could not insert into 'servers:' block; appending instead." >&2
        printf '\n' >>"$CONFIG_PATH"
        append_line "  - $SERVER_URL"
    fi
fi

# Best-effort: stop the running TMLoader so it picks up the change on next launch.
if pgrep -f 'TMLoader.exe' >/dev/null 2>&1; then
    pkill -f 'TMLoader.exe' 2>/dev/null || true
    echo "TMFLiveReplay installed! TMLoader was closed, reopen it so TMFLiveReplay gets fetched!"
else
    echo "TMFLiveReplay installed! Open TMLoader so it gets fetched!"
fi
