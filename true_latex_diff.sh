#!/bin/bash

# Function to recursively process LaTeX files in a directory
process_directory() {
    local original_dir="$1"
    local new_dir="$2"
    local output_dir="$3"

    # Loop through files and directories in the original directory
    for item in "$original_dir"/*; do
      echo "Visiting $item"

        local relative_path=${item#$original_dir}
        local new_item="$new_dir/$relative_path"

        if [ -d "$item" ]; then
            if [ -d "$new_item" ]; then
                local subdir_name=$(basename "$item")
                process_directory "$item" "$new_item" "$output_dir/$subdir_name"
            fi
        elif [ -f "$item" ] && [[ "$item" == *.tex ]]; then
            local file_name=$(basename "$item")
            local relative_dir=$(dirname "${item#$original_dir}")
            local output_subdir="$output_dir/$relative_dir"

            # Create output directory if it doesn't exist
            mkdir -p "$output_subdir"

            # Run latexdiff on the LaTeX file
            latexdiff "$item" "${new_dir}/${relative_dir}/$file_name" > "$output_subdir/$file_name"
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

original_src="$1"
new_src="$2"
output_src="$3"

# Check if source directories exist
if [ ! -d "$original_src" ] || [ ! -d "$new_src" ]; then
    echo "Source directories do not exist."
    exit 1
fi

# Copy directories and their content from original_src to new_src
rsync -av "$new_src" "$output_src" > /dev/null


# Run latexdiff recursively on the source directories
process_directory "$original_src" "$new_src" "$output_src"


echo "LaTeX diff generated successfully in $output_src."

