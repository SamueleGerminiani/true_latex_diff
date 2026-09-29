#!/bin/bash

# Normalize a LaTeX file so latexdiff tokenizes commands correctly:
# "\cmd {arg}" / "\cmd [opt]" -> "\cmd{arg}" / "\cmd[opt]".
# In TeX the space after a control word is ignored anyway, so this is
# semantically identical, but latexdiff treats "\cmd " and "{arg}" as
# separate tokens and can emit broken markup such as "\DIFdel{\ref }".
normalize_tex() {
    perl -pe 's/(\\[a-zA-Z@]+\*?)[ \t]+(?=[\{\[])/$1/g' "$1" > "$2"
}

# Function to recursively process LaTeX files in a directory.
# Walks the new version, so files and directories that only exist there
# are diffed against an empty original and show up as added content.
process_directory() {
    local original_dir="$1"
    local new_dir="$2"
    local output_dir="$3"

    # Loop through files and directories in the new directory
    for new_item in "$new_dir"/*; do
        local name=$(basename "$new_item")
        local item="$original_dir/$name"
        local out_item="$output_dir/$name"

        if [ -d "$new_item" ]; then
            process_directory "$item" "$new_item" "$out_item"
        elif [ -f "$new_item" ] && [[ "$new_item" == *.tex ]]; then
            normalize_tex "$new_item" "$tmp_dir/new.tex"
            if [ -f "$item" ]; then
                # Skip unchanged files (output keeps the copy of the new version),
                # except the main file, which needs the latexdiff preamble
                if cmp -s "$item" "$new_item" && ! grep -q '\\begin{document}' "$item"; then
                    continue
                fi
                echo "Diffing ${new_item#$new_src/}"
                normalize_tex "$item" "$tmp_dir/old.tex"
            else
                echo "Diffing ${new_item#$new_src/} (new file)"
                # latexdiff requires both files to have a preamble or neither:
                # for a new main file, use its preamble with an empty body
                perl -0pe 's/(\\begin\{document\}).*/$1\n\\end{document}\n/s or $_ = ""' \
                    "$tmp_dir/new.tex" > "$tmp_dir/old.tex"
            fi

            mkdir -p "$output_dir"

            # Run latexdiff on the LaTeX file, then move "\end{env}" onto its own
            # line when it follows the closing brace of latexdiff markup:
            # comment-package environments (e.g. acmart's acks) only recognize
            # "\end{env}" at the start of a line
            if ! latexdiff "$tmp_dir/old.tex" "$tmp_dir/new.tex" 2> "$tmp_dir/err.log" \
                | perl -pe 's/\}[ \t]*(?=\\end\{)/}\n/g' > "$out_item"; then
                echo "  latexdiff failed on $name, keeping new version:"
                sed 's/^/    /' "$tmp_dir/err.log"
                cp "$new_item" "$out_item"
            fi
        fi
    done
}

# Check if latexdiff is installed
if ! command -v latexdiff &> /dev/null; then
    echo "latexdiff is not installed. Please install it first."
    exit 1
fi

# Check if correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <original_src_directory> <new_src_directory> <output_src_directory>"
    exit 1
fi

original_src="${1%/}"
new_src="${2%/}"
output_src="${3%/}"

# Check if source directories exist
if [ ! -d "$original_src" ] || [ ! -d "$new_src" ]; then
    echo "Source directories do not exist."
    exit 1
fi

set -o pipefail

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Copy the content of new_src (figures, bib, cls, ...) into output_src
# (trailing slash: copy the content, not the directory itself)
mkdir -p "$output_src"
rsync -a "$new_src/" "$output_src/"

# Run latexdiff recursively on the source directories
process_directory "$original_src" "$new_src" "$output_src"

# Drop the wavy underline from added text, leaving it blue only. Applied to
# every latexdiff preamble line in the output, including stale preambles left
# in the sources, since \providecommand keeps whichever definition comes first
find "$output_src" -name '*.tex' -exec perl -i -pe \
    's/\\uwave\{#1\}/#1/g, s/\\color\{blue\}\\uwave\]/\\color{blue}]/g if /%DIF PREAMBLE/' {} +

echo "LaTeX diff generated successfully in $output_src."
