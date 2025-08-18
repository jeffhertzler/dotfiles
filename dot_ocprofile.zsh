function oc() {
  local profile=""
  local args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      --profile=*|-P=*)
        profile="${1#*=}"
        shift
        ;;
      --profile|-P)
        if [[ -n "$2" && "$2" != -* ]]; then
          profile="$2"
          shift 2
        else
          echo "Error: --profile/-P requires a value (personal|work)"
          return 1
        fi
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "$profile" ]]; then
    if [[ "$profile" != "personal" && "$profile" != "work" ]]; then
      echo "Error: profile must be 'personal' or 'work'"
      return 1
    fi
    ocpr "$profile"
  fi

  opencode "${args[@]}"
}

function ocpr() {
  local auth_dir="$HOME/.local/share/opencode"
  local auth_path="$auth_dir/auth.json"
  local personal_auth_path="$auth_dir/personal.json"
  local work_auth_path="$auth_dir/work.json"

  local config_dir="$HOME/.config/opencode"
  local config_path="$config_dir/opencode.json"
  local personal_config_path="$config_dir/personal.json"
  local work_config_path="$config_dir/work.json"

  if [ -z "$1" ]; then
    if [ -L "$auth_path" ]; then
      local target=$(readlink "$auth_path")
      if [[ "$target" == *"personal"* ]]; then
        echo "personal"
      elif [[ "$target" == *"work"* ]]; then
        echo "work"
      else
        echo "unknown"
      fi
    else
      echo "not a symlink"
    fi
  elif [ "$1" = "personal" ]; then
    if [ -f "$personal_auth_path" ]; then
      rm -f "$auth_path"
      ln -s "$personal_auth_path" "$auth_path"
      if [ -f "$personal_config_path" ]; then
        rm -f "$config_path"
        ln -s "$personal_config_path" "$config_path"
      else
        echo "Warning: $personal_config_path not found"
      fi
      echo "Switched to personal"
    else
      echo "Error: $personal_auth_path not found"
    fi
  elif [ "$1" = "work" ]; then
    if [ -f "$work_auth_path" ]; then
      rm -f "$auth_path"
      ln -s "$work_auth_path" "$auth_path"
      if [ -f "$work_config_path" ]; then
        rm -f "$config_path"
        ln -s "$work_config_path" "$config_path"
      else
        echo "Warning: $work_config_path not found"
      fi
      echo "Switched to work"
    else
      echo "Error: $work_auth_path not found"
    fi
  else
    echo "Usage: ocpr [personal|work]"
    echo "Current profile: $(ocpr)"
  fi
}
