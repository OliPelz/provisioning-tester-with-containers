# here we put small functions we need in makefile but are too big
# to use directly 

render_template() {
  local src_file="$1"
  local dest_file="$2"

  # Replace $$ and \$ with placeholders to prevent envsubst from substituting them
  local temp
  temp=$(sed -e 's/\$\$/__DOUBLE_DOLLAR__/g' -e 's/\\\$/__ESCAPED_DOLLAR__/g' "$src_file")

  # Run envsubst on the temp content
  local rendered
  rendered=$(echo "$temp" | envsubst)

  # Restore placeholders back to their original form
  rendered="${rendered//__DOUBLE_DOLLAR__/\$}"
  rendered="${rendered//__ESCAPED_DOLLAR__/\$}"

  if [[ "$DRY_RUN" == true ]]; then
    echo "# ---render.sh: dry-run would render to file: $dest_file"
    echo "$rendered"
  else
    mkdir -p "$(dirname "$dest_file")"
    echo "$rendered" > "$dest_file"
    echo "Rendered $dest_file"
  fi
}
