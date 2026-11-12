#!/usr/bin/env bash
# Appends today's numbers for this repository to CSV files outside the working tree: stars, forks and open issues,
# the traffic of the last 14 days (views, clones, referrers), and the download count of every release asset.
# GitHub keeps traffic for 14 days and download counts have no history, so a record exists only if this runs
# regularly; once a day is enough. Nothing is read from, or added to, the app: every number comes from GitHub's API.
#
# Usage: scripts/traffic-snapshot.sh [--dir PATH]
#
# The files (created with a header row on first use) are written to --dir, $TRREK_METRICS_DIR or
# ~/Library/Application Support/trrek-metrics:
#   daily.csv      date,stars,forks,open_issues,views_14d,visitors_14d,clones_14d,cloners_14d
#   views.csv      day,views,visitors          one row per day; a day's row is replaced while it is still changing
#   referrers.csv  date,referrer,views,visitors   the top referrers of the last 14 days, as of that date
#   downloads.csv  date,tag,asset,downloads    cumulative; subtract the previous day's row for a daily figure
# Text fields (referrer, tag, asset) are written in double quotes.
#
# Download counts include the app's own updates and any package manager, not only people who clicked Download.
# Needs gh, signed in with push access to the repository (the traffic endpoints require it).
set -euo pipefail

cd "$(dirname "$0")/.."

DIR="${TRREK_METRICS_DIR:-$HOME/Library/Application Support/trrek-metrics}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="${2:?--dir needs a value}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "traffic-snapshot: $*" >&2; exit 1; }

# A relative path would resolve inside the repository, which the script has just changed into.
[[ "$DIR" == /* ]] || fail "the directory must be an absolute path: $DIR"

command -v gh >/dev/null || fail "gh is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in"

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || fail "could not read the repository name"
TODAY="$(date -u +%F)"
mkdir -p "$DIR"

# Writes the header row $2 to file $1 when the file does not exist yet.
header() { [[ -f "$1" ]] || printf '%s\n' "$2" > "$1"; }

# Removes the rows of file $1 whose first field is $2, so a second run on the same day replaces the first.
drop_rows() {
    local file="$1" key="$2" kept
    kept="$(mktemp)"
    awk -F, -v key="$key" 'NR == 1 || $1 != key' "$file" > "$kept"
    mv "$kept" "$file"
}

header "$DIR/daily.csv" "date,stars,forks,open_issues,views_14d,visitors_14d,clones_14d,cloners_14d"
header "$DIR/views.csv" "day,views,visitors"
header "$DIR/referrers.csv" "date,referrer,views,visitors"
header "$DIR/downloads.csv" "date,tag,asset,downloads"

COUNTS="$(gh api "repos/$REPO" --jq '[.stargazers_count, .forks_count, .open_issues_count] | @csv')" \
    || fail "could not read the repository"
VIEWS="$(gh api "repos/$REPO/traffic/views" --jq '[.count, .uniques] | @csv')" \
    || fail "could not read the traffic (push access is required)"
CLONES="$(gh api "repos/$REPO/traffic/clones" --jq '[.count, .uniques] | @csv')" || fail "could not read the clones"

drop_rows "$DIR/daily.csv" "$TODAY"
printf '%s,%s,%s,%s\n' "$TODAY" "$COUNTS" "$VIEWS" "$CLONES" >> "$DIR/daily.csv"

# Per-day views: the newest value of a day wins, since today's count keeps growing until midnight UTC.
DAYS="$(gh api "repos/$REPO/traffic/views" --jq '.views[] | "\(.timestamp[0:10]),\(.count),\(.uniques)"')" \
    || fail "could not read the daily views"
MERGED="$(mktemp)"
{
    head -n 1 "$DIR/views.csv"
    { tail -n +2 "$DIR/views.csv"; [[ -z "$DAYS" ]] || printf '%s\n' "$DAYS"; } \
        | awk -F, '{ rows[$1] = $0 } END { for (day in rows) print rows[day] }' | sort
} > "$MERGED"
mv "$MERGED" "$DIR/views.csv"

# Each list is read in full before its file is touched, so a failed request leaves the file as it was.
REFERRERS="$(gh api "repos/$REPO/traffic/popular/referrers" --jq '.[] | [.referrer, .count, .uniques] | @csv')" \
    || fail "could not read the referrers"
DOWNLOADS="$(gh api --paginate "repos/$REPO/releases" \
    --jq '.[] | .tag_name as $tag | .assets[] | [$tag, .name, .download_count] | @csv')" \
    || fail "could not read the releases"

drop_rows "$DIR/referrers.csv" "$TODAY"
[[ -z "$REFERRERS" ]] || printf '%s\n' "$REFERRERS" | sed "s/^/$TODAY,/" >> "$DIR/referrers.csv"

drop_rows "$DIR/downloads.csv" "$TODAY"
[[ -z "$DOWNLOADS" ]] || printf '%s\n' "$DOWNLOADS" | sed "s/^/$TODAY,/" >> "$DIR/downloads.csv"

echo "traffic-snapshot: $TODAY recorded in $DIR"
tail -n 1 "$DIR/daily.csv"
