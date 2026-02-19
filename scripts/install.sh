#!/usr/bin/env bash
set -e

os=$(uname -s)
arch=$(uname -m)

if [[ "$os" == "Linux" && "$arch" == "x86_64" ]]; then
    binary_name="cadence-x86_64-linux-gnu"
elif [[ "$os" == "Linux" && "$arch" == "aarch64" ]]; then
    binary_name="cadence-aarch64-linux-gnu"
elif [[ "$os" == "Darwin" && "$arch" == "x86_64" ]]; then
    binary_name="cadence-x86_64-macos"
elif [[ "$os" == "Darwin" && "$arch" == "arm64" ]]; then
    binary_name="cadence-aarch64-macos"
else
    echo "error: unsupported operating system or architecture"
    exit 1
fi

install_dir="$HOME/.local/bin"
mkdir -p "$install_dir"

download_url="https://github.com/meechdw/cadence/releases/latest/download/$binary_name"
temp_file="${TMPDIR:-/tmp}/cadence"

curl -L "$download_url" -o "$temp_file"
mv "$temp_file" "$install_dir/cadence"
chmod +x "$install_dir/cadence"

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "\nWarning: ~/.local/bin is not in your PATH"
    echo "To complete installation, add the following line to your shell profile:"
    echo "export PATH='$HOME/.local/bin:$PATH'"
    echo -e "\nThen restart your terminal or re-source your shell profile."
else
    echo -e "\nInstallation complete!"
fi
