# Source this after setting script_directory to the calling script's directory.
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
viewer_root="$repository_root/apps/viewer"
native_build_root="$repository_root/build"
