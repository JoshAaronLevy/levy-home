#!/usr/bin/env bash

# Advisory Swift maintainability report. This intentionally exits 0 even when
# thresholds are exceeded so it can run locally or in CI without blocking work.

WARN_LINES="${SWIFT_HEALTH_WARN_LINES:-500}"
INVESTIGATE_LINES="${SWIFT_HEALTH_INVESTIGATE_LINES:-1000}"
TOP_LIMIT="${SWIFT_HEALTH_TOP_LIMIT:-15}"
DECL_LIMIT="${SWIFT_HEALTH_DECL_LIMIT:-12}"

roots=("$@")
if [ "${#roots[@]}" -eq 0 ]; then
    roots=("LevyHome" "LevyHomeTests")
fi

files_tmp="$(mktemp)"
line_counts_tmp="$(mktemp)"
decl_counts_tmp="$(mktemp)"
trap 'rm -f "$files_tmp" "$line_counts_tmp" "$decl_counts_tmp"' EXIT

for root in "${roots[@]}"; do
    if [ -d "$root" ]; then
        find "$root" -type f -name '*.swift' -print >> "$files_tmp"
    elif [ -f "$root" ] && [ "${root##*.}" = "swift" ]; then
        printf '%s\n' "$root" >> "$files_tmp"
    fi
done

sort -u "$files_tmp" -o "$files_tmp"

if [ ! -s "$files_tmp" ]; then
    echo "Swift Project Health"
    echo
    echo "No Swift files found for: ${roots[*]}"
    echo
    echo "Advisory only: no checks failed."
    exit 0
fi

while IFS= read -r file; do
    lines="$(wc -l < "$file" | tr -d '[:space:]')"
    declarations="$(
        awk '
            /^[[:space:]]/ { next }
            /^$/ { next }
            /^\/\// { next }
            /^import[[:space:]]/ { next }
            /^@[[:alnum:]_]+/ { next }
            /^(public |internal |private |fileprivate |open )?(final )?(struct|class|enum|actor|protocol|extension|func|let|var|typealias)[[:space:]]/ { count++; next }
            /^#Preview[[:space:]]*\{/ { count++; next }
            END { print count + 0 }
        ' "$file"
    )"

    printf '%s\t%s\n' "$lines" "$file" >> "$line_counts_tmp"
    printf '%s\t%s\n' "$declarations" "$file" >> "$decl_counts_tmp"
done < "$files_tmp"

file_count="$(wc -l < "$files_tmp" | tr -d '[:space:]')"
total_lines="$(awk -F '\t' '{ sum += $1 } END { print sum + 0 }' "$line_counts_tmp")"
warning_count="$(awk -F '\t' -v warn="$WARN_LINES" '$1 >= warn { count++ } END { print count + 0 }' "$line_counts_tmp")"
declaration_count="$(awk -F '\t' -v limit="$DECL_LIMIT" '$1 >= limit { count++ } END { print count + 0 }' "$decl_counts_tmp")"

echo "Swift Project Health"
echo
echo "Scope: ${roots[*]}"
echo "Swift files: $file_count"
echo "Total Swift lines: $total_lines"
echo "Line thresholds: warn >= $WARN_LINES, investigate >= $INVESTIGATE_LINES"
echo "Top-level declaration report threshold: >= $DECL_LIMIT"
echo

echo "Top $TOP_LIMIT Swift files by line count:"
sort -nr "$line_counts_tmp" | head -n "$TOP_LIMIT" | awk -F '\t' '{ printf "  %5d  %s\n", $1, $2 }'
echo

echo "Files at or above line-count thresholds:"
if [ "$warning_count" -eq 0 ]; then
    echo "  None"
else
    sort -nr "$line_counts_tmp" | awk -F '\t' -v warn="$WARN_LINES" -v investigate="$INVESTIGATE_LINES" '
        $1 >= warn {
            label = ($1 >= investigate) ? "investigate" : "warn"
            printf "  %-11s %5d  %s\n", label, $1, $2
        }
    '
fi
echo

echo "Files with many top-level declarations:"
if [ "$declaration_count" -eq 0 ]; then
    echo "  None"
else
    sort -nr "$decl_counts_tmp" | awk -F '\t' -v limit="$DECL_LIMIT" '
        $1 >= limit {
            printf "  %5d  %s\n", $1, $2
        }
    '
fi
echo

echo "Advisory only: this script exits 0 even when reports include warnings."
