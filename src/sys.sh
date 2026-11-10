# shellcheck shell=bash
# =============================================================================
#  SYSTEM & ENVIRONMENT DETECTION
# =============================================================================

# Detect system architecture normalized.
_get_arch() {
    if [[ -z "${_SYS_ARCH_CACHE:-}" ]]; then
        local m
        m="$(uname -m 2>/dev/null || echo "unknown")"
        case "$m" in
            x86_64|amd64) _SYS_ARCH_CACHE="x86_64" ;;
            aarch64|arm64|armv8*) _SYS_ARCH_CACHE="arm64" ;;
            *) _SYS_ARCH_CACHE="$m" ;;
        esac
    fi
    printf '%s' "$_SYS_ARCH_CACHE"
}

# Detect package manager
_detect_pm() {
    local pm
    for pm in apt apt-get dnf pacman zypper apk brew mise; do
        command -v "$pm" >/dev/null 2>&1 && printf '%s' "$pm" && return
    done
    printf 'unknown'
}

# Returns 0 on WSL, 1 otherwise.
_is_wsl() {
    if [[ -z "${_SYS_IS_WSL_CACHE:-}" ]]; then
        if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] \
        || grep -qi 'microsoft' /proc/version 2>/dev/null; then
            _SYS_IS_WSL_CACHE=0
        else
            _SYS_IS_WSL_CACHE=1
        fi
    fi
    return "$_SYS_IS_WSL_CACHE"
}

# Returns 0 inside Docker/OCI container, 1 otherwise.
_is_container() {
    if [[ -z "${_SYS_IS_CONTAINER_CACHE:-}" ]]; then
        if [[ -f /.dockerenv || -f /run/.containerenv || -f /run/systemd/container ]] \
        || grep -qE '(docker|containerd|kubepods|lxc)' /proc/1/cgroup /proc/self/cgroup 2>/dev/null \
        || { command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --container >/dev/null 2>&1; }; then
            _SYS_IS_CONTAINER_CACHE=0
        else
            _SYS_IS_CONTAINER_CACHE=1
        fi
    fi
    return "$_SYS_IS_CONTAINER_CACHE"
}

# Detect system environment
_get_env() {
    if [[ -z "${_SYS_ENV_CACHE:-}" ]]; then
        if [[ -n "${ENV:-}" ]]; then
            _SYS_ENV_CACHE="$ENV"
        elif _is_wsl; then
            _SYS_ENV_CACHE="wsl"
        elif [[ -f /etc/cloud/cloud.cfg || -f /etc/digitalocean || -d /etc/oracle-cloud-agent ]] \
             || { command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --vm >/dev/null 2>&1; } \
             || [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] \
             || { ! command -v xset >/dev/null 2>&1 && [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; }; then
            _SYS_ENV_CACHE="vps"
        else
            _SYS_ENV_CACHE="desktop"
        fi
    fi
    printf '%s' "$_SYS_ENV_CACHE"
}

# Detect system distribution name.
_get_distro_name() {
    if [[ -z "${_SYS_DISTRO_CACHE:-}" ]]; then
        if [[ -f /etc/os-release ]]; then
            local name=""
            # shellcheck disable=SC1091
            name="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-$NAME}")"
            if [[ -n "$name" ]]; then
                _SYS_DISTRO_CACHE="$name"
                printf '%s' "$_SYS_DISTRO_CACHE"
                return 0
            fi
        fi
        _SYS_DISTRO_CACHE="$(uname -s)"
    fi
    printf '%s' "$_SYS_DISTRO_CACHE"
}

# Aggregate detected environment conditions.
_get_detected_conds() {
    if _is_wsl; then
        printf 'wsl'
    elif _is_container; then
        printf 'container'
    elif [[ "$(_get_env)" != "default" && -n "$(_get_env)" ]]; then
        printf '%s' "$(_get_env)"
    else
        local os
        os="$(uname -s 2>/dev/null || echo "linux")"
        printf '%s' "${os,,}"
    fi
}

_is_user_path() {
    [[ -n "${1:-}" && ( "$1" == "$HOME/"* || "$1" == "/home/"* ) ]]
}

_is_system_path() {
    [[ -n "${1:-}" ]] && ! _is_user_path "$1"
}

# Initialize system detection caches in the parent shell to avoid subshell detection overhead
_init_sys_info() {
    if [[ -z "${_SYS_ARCH_CACHE:-}" ]]; then
        _get_arch >/dev/null || true
    fi
    if [[ -z "${_SYS_ENV_CACHE:-}" ]]; then
        _get_env >/dev/null || true
    fi
    if [[ -z "${_SYS_IS_WSL_CACHE:-}" ]]; then
        _is_wsl || true
    fi
    if [[ -z "${_SYS_IS_CONTAINER_CACHE:-}" ]]; then
        _is_container || true
    fi
    if [[ -z "${_SYS_OS_CACHE:-}" ]]; then
        _SYS_OS_CACHE="$(uname -s 2>/dev/null || echo "Linux")"
    fi
    return 0
}

# Check if binary exists in scoped search paths
_check_bins_scoped() {
    REPLY=""
    REPLY_PATH=""
    local b _bins scope="${2:-any}"
    IFS=',' read -ra _bins <<< "$1"
    for b in "${_bins[@]}"; do
        b="${b#"${b%%[![:space:]]*}"}"
        b="${b%"${b##*[![:space:]]}"}"
        [[ -z "$b" ]] && continue

        local -a candidates=()
        local -A _seen=()
        _add_cand() {
            local c="$1"
            if [[ -n "$c" && -z "${_seen["$c"]:-}" ]]; then
                _seen["$c"]=1
                candidates+=("$c")
            fi
        }

        if [[ "$b" == /* && ( -e "$b" || -r "$b" ) ]]; then
            _add_cand "$b"
        fi
        local p
        while IFS= read -r p; do
            [[ -n "$p" && -x "$p" ]] && _add_cand "$p"
        done < <(type -aP "$b" 2>/dev/null || true)

        if [[ "$scope" == "user" || "$scope" == "any" ]]; then
            local udir
            for udir in "${XDG_BIN_HOME:-$HOME/.local/bin}" "$HOME/.local/bin" "$HOME/.cargo/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" "$HOME/.local/share/mise/shims" "$HOME/.bun/bin" "$HOME/go/bin" "$HOME/.atuin/bin" "$HOME/.gemini/antigravity-cli/bin" "$HOME/.opencode/bin" "$HOME/.codex/bin" "$HOME/.grok/bin" "$HOME/.kilo/bin" "$HOME/.copilot/bin" "$HOME/.muse/bin"; do
                [[ -x "$udir/$b" ]] && _add_cand "$udir/$b"
            done

            local mise_cmd=""
            if command -v mise >/dev/null 2>&1; then
                mise_cmd="mise"
            elif [[ -x "$HOME/.local/bin/mise" ]]; then
                mise_cmd="$HOME/.local/bin/mise"
            fi
            if [[ -n "$mise_cmd" ]]; then
                local mise_bin
                mise_bin="$("$mise_cmd" which "$b" 2>/dev/null || true)"
                [[ -n "$mise_bin" && -x "$mise_bin" ]] && _add_cand "$mise_bin"
            fi

            local s_root
            for s_root in "${SDKMAN_DIR:-}" "${XDG_DATA_HOME:-$HOME/.local/share}/sdkman" "$HOME/.sdkman"; do
                [[ -z "$s_root" ]] && continue
                if [[ ( "$b" == "sdk" || "$b" == "sdkman" ) && -s "$s_root/bin/sdkman-init.sh" ]]; then
                    _add_cand "$s_root/bin/sdkman-init.sh"
                fi
                if [[ -d "$s_root/candidates" ]]; then
                    local s_cand
                    for s_cand in "$s_root/candidates"/*; do
                        [[ -x "$s_cand/current/bin/$b" ]] && _add_cand "$s_cand/current/bin/$b"
                    done
                fi
            done
        fi

        if [[ "$scope" == "system" || "$scope" == "any" ]]; then
            local sdir
            for sdir in "/usr/local/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin" "/opt/bin"; do
                [[ -x "$sdir/$b" ]] && _add_cand "$sdir/$b"
            done
        fi

        local found_bin="" found_path=""
        for p in "${candidates[@]}"; do
            case "$scope" in
                system)
                    if _is_system_path "$p"; then
                        found_bin="$b"
                        found_path="$p"
                        break
                    fi
                    ;;
                user)
                    if _is_user_path "$p"; then
                        found_bin="$b"
                        found_path="$p"
                        break
                    fi
                    ;;
                *)
                    found_bin="$b"
                    found_path="$p"
                    break
                    ;;
            esac
        done

        if [[ -n "$found_path" ]]; then
            REPLY="$found_bin"
            REPLY_PATH="$found_path"
            return 0
        fi
    done
    return 1
}

_check_bins() {
    _check_bins_scoped "$@"
}

# Quick non-blocking network probe
_check_network() {
    [[ "${OFFLINE:-false}" == true ]] && return 1
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 2 --max-time 3 -o /dev/null https://1.1.1.1 2>/dev/null \
        || curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 2 --max-time 3 -o /dev/null https://cloudflare.com 2>/dev/null \
        || return 1
        return 0
    fi
    return 0
}

# Check disk space (minimum MB required, default 500MB)
_check_disk_space() {
    local min_mb="${1:-500}"
    local path="${2:-$HOME}"
    [[ "${DRY_RUN:-false}" == true ]] && return 0
    if command -v df >/dev/null 2>&1; then
        local avail_kb
        avail_kb="$(df -kP "$path" 2>/dev/null | awk 'NR==2 {print $4}')"
        if [[ -n "$avail_kb" && "$avail_kb" =~ ^[0-9]+$ ]]; then
            local avail_mb=$(( avail_kb / 1024 ))
            if [[ $avail_mb -lt $min_mb ]]; then
                log_error "Insufficient disk space on ${path}: ${avail_mb}MB available, minimum ${min_mb}MB required."
                return 1
            fi
        fi
    fi
    return 0
}
