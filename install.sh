#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app_name="Cursor Usage Micro"
usage_micro_install_dir=${USAGE_MICRO_INSTALL_DIR:-"$HOME/Applications"}
launch_after_install=1

if (( $# > 1 )) || [[ ${1:-} != "" && ${1:-} != "--no-launch" ]]; then
  print -u2 -- "Usage: ./install.sh [--no-launch]"
  exit 64
fi

if [[ ${1:-} == "--no-launch" ]]; then
  launch_after_install=0
fi

if [[ "$usage_micro_install_dir" != /* || "$usage_micro_install_dir" == "/" || "$usage_micro_install_dir" == "$HOME" ]]; then
  print -u2 -- "USAGE_MICRO_INSTALL_DIR must be a specific absolute directory."
  exit 64
fi

"$project_dir/build.sh"

built_app="$project_dir/build/$app_name.app"
if [[ ! -e "$built_app" && ! -L "$built_app" ]]; then
  print -u2 -- "The build did not produce $built_app"
  exit 1
fi

source_app=${built_app:A}
codesign --verify --deep --strict "$source_app"

mkdir -p "$usage_micro_install_dir"
staging_root=$(mktemp -d "$usage_micro_install_dir/.cursor-usage-micro-install.XXXXXX")
staging_app="$staging_root/$app_name.app"
destination_app="$usage_micro_install_dir/$app_name.app"
backup_app="$staging_root/previous.app"
destination_was_moved=0

cleanup() {
  if (( destination_was_moved == 1 )) && [[ ! -e "$destination_app" && ! -L "$destination_app" ]] && [[ -e "$backup_app" || -L "$backup_app" ]]; then
    mv "$backup_app" "$destination_app"
  fi
  rm -rf "$staging_root"
}
trap cleanup EXIT INT TERM

chmod 700 "$staging_root"
ditto --noextattr --noqtn "$source_app" "$staging_app"
codesign --verify --deep --strict "$staging_app"

if [[ -e "$destination_app" || -L "$destination_app" ]]; then
  mv "$destination_app" "$backup_app"
  destination_was_moved=1
fi

mv "$staging_app" "$destination_app"
destination_was_moved=0
rm -rf "$backup_app"
rmdir "$staging_root"
trap - EXIT INT TERM

echo "Installed $destination_app"

if (( launch_after_install == 1 )) && ! open "$destination_app"; then
  print -u2 -- "The app was installed but could not be opened automatically."
fi
