#!/bin/bash
#set -x
# Check if the input file is provided
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <file_with_filenames>"
  exit 1
fi

# Input file containing filenames
input_file="$1"

# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: File '$input_file' not found."
  exit 1
fi

# Number of file contents per batch
batch_size=4
batch_number=1
batch_file="batch${batch_number}.txt"

# Initialize a counter
counter=0

rm batch*.txt
# Process each line in the input file
while IFS= read -r line; do
  # Skip empty lines and lines starting with #
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  # Extract the first word (script name) from the line
  script_name=$(echo "$line" | awk '{print $1}')

  script_path=./bash_scripts/roles/$script_name

  # Add the file content to the current batch file
  echo "# ------- $script_name" >> "$batch_file"
  if [[ -f "$script_path" ]]; then
    cat "$script_path" >> "$batch_file"
  else
    echo "Error: File '$script_name' not found." >> "$batch_file"
  fi
  echo >> "$batch_file" # Add a blank line for separation
  ((counter++))

  # If the batch size is reached, start a new batch file
  if (( counter % batch_size == 0 )); then
    ((batch_number++))
    batch_file="batch${batch_number}.txt"
  fi
done < "$input_file"

echo "Batches created successfully."


