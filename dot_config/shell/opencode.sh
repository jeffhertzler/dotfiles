# Shared OpenCode account launchers. Credential files are machine-local and
# intentionally unmanaged by Chezmoi.
_opencode_profile() {
  local profile="$1"
  shift

  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local auth_dir="$data_home/opencode"
  local profile_auth="$auth_dir/profiles/$profile/auth.json"
  local active_auth="$auth_dir/auth.json"
  local temporary_link="$auth_dir/.auth.json.$$"

  if ! command -v opencode >/dev/null 2>&1; then
    printf 'OpenCode is not installed or is not on PATH.\n' >&2
    return 1
  fi

  if [ ! -f "$profile_auth" ]; then
    printf 'OpenCode %s credentials are not initialized at %s.\n' \
      "$profile" "$profile_auth" >&2
    return 1
  fi

  rm -f "$temporary_link"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      MSYS=winsymlinks:nativestrict ln -s "profiles/$profile/auth.json" "$temporary_link" || return 1
      ;;
    *)
      ln -s "profiles/$profile/auth.json" "$temporary_link" || return 1
      ;;
  esac

  if ! mv -f "$temporary_link" "$active_auth"; then
    rm -f "$temporary_link"
    return 1
  fi

  command opencode "$@"
}

ocp() { _opencode_profile personal "$@"; }
ocw() { _opencode_profile work "$@"; }
