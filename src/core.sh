# shellcheck shell=bash
# =============================================================================
#  CORE FOUNDATION (Environment, Traps, Supervisor & Sudo)
# =============================================================================

set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true  # Bash 4.4+: command substitutions inherit set -e

# Enforce secure umask
umask 027

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "$SCRIPT_DIR" == */src/* || "$SCRIPT_DIR" == */src ]]; then
        SCRIPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
        [[ "$SCRIPT_DIR" == */src ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
fi
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
PACKAGES_DIR="${PACKAGES_DIR:-$SCRIPT_DIR/packages}"
GROUPS_CONF="${GROUPS_CONF:-$PACKAGES_DIR/_groups.conf}"
CONFIG_FILE="${CONFIG_FILE:-}"
BACKUP_DIR="${BACKUP_DIR:-}"
_get_backup_dir() {
    if [[ -z "${BACKUP_DIR:-}" ]]; then
        local bdir="$HOME/.dotfiles.bak/$(date +%Y%m%d_%H%M%S)"
        (umask 077 && mkdir -p "$bdir")
        BACKUP_DIR="$bdir"
    fi
}

# ---------------------------------------------------------------------------
# Mutable globals: runtime state
# ---------------------------------------------------------------------------
DRY_RUN=false
VERBOSE="${VERBOSE:-false}"
VERIFY_SCRIPTS="${VERIFY_SCRIPTS:-false}"
FORCE="${FORCE:-false}"
ENV="${ENV:-}"
OFFLINE="${OFFLINE:-false}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-300}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-15}"
BACKUP_COUNT=0
SUDO_PID=""

# Failure and warning registries
declare -a _FAILED_PACKAGES=()
declare -A _FAILURE_REASONS=()
declare -a _WARNING_MESSAGES=()
declare -A _DEP_RESOLVE_STACK=()
_LAST_CMD_ERROR=""

# System detection and lookup caches
_SYS_ARCH_CACHE=""
_SYS_DISTRO_CACHE=""
_SYS_ENV_CACHE=""
_SYS_IS_WSL_CACHE=""
_SYS_IS_CONTAINER_CACHE=""

# User settings: overridden by config or environment
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"          # set in config/env to avoid interactive email prompt
GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-main}"
GIT_EDITOR="${GIT_EDITOR:-}"
GIT_SIGNING_KEY="${GIT_SIGNING_KEY:-}"

# Optional packages allow-list
if [[ -z "${OPTIONAL_PACKAGES+x}" ]]; then
    declare -a OPTIONAL_PACKAGES=()
fi

# Package group filter (empty array = install all groups)
if [[ -z "${INSTALL_GROUPS+x}" ]]; then
    declare -a INSTALL_GROUPS=()
fi

# Package manager & metrics state
_PM=""
SKIP_UPGRADE=false
declare -i _INSTALLED_PACKAGES_COUNT=0

# In-memory package & group manifest cache
declare -a _GROUPS_LIST=()
declare -A _GROUP_DESCS=() _GROUP_PACKAGES_MAP=() _GROUP_OPTIONAL=()
declare -i _GROUPS_LOADED=0

declare -A _CONF_PARSED=()
declare -A _CONF_PKG_NAME=()
declare -A _CONF_PKG_BIN=()
declare -A _CONF_PKG_DESC=()
declare -A _CONF_PKG_SCOPE=()
declare -A _CONF_PKG_INSTALL=()
declare -A _CONF_PKG_OPTS=()
declare -A _CONF_BASHRC=()
declare -A _CONF_TEMPLATES=()

declare -A _CONF_PKG_KEYS=()
declare -A _CONF_PKG_DISABLED=()
declare -A _CONF_PKG_DECLINED=()
declare -A _CONF_BASHRC_BUF=()
declare -A _CONF_BASHRC_DIS=()
declare -A _CONF_TMPL_BUF=()
declare -A _CONF_TMPL_DIS=()

declare -i _CONF_CASCADE_DONE=0
declare -a _TRACKED_TMP_FILES=()
declare -a _TRACKED_CHILD_PIDS=()

# ---------------------------------------------------------------------------
# Cleanup & signal traps
# ---------------------------------------------------------------------------
_cleanup() {
    local code="${1:-$?}"
    [[ -t 2 ]] && printf '\033[?25h\033]0;\007' >&2 || true
    [[ -n "$SUDO_PID" ]] && kill "$SUDO_PID" 2>/dev/null || true

    # Clean tracked background children
    if [[ ${#_TRACKED_CHILD_PIDS[@]} -gt 0 ]]; then
        local cpid
        for cpid in "${_TRACKED_CHILD_PIDS[@]}"; do
            kill -TERM "$cpid" 2>/dev/null || true
            kill -KILL "$cpid" 2>/dev/null || true
        done
        _TRACKED_CHILD_PIDS=()
    fi

    # Remove backup dir if empty (no files backed up)
    if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]] \
    && [[ -z "$(find "$BACKUP_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        rm -rf "$BACKUP_DIR"
    fi
    if [[ -n "${_BUNDLE_WORKDIR:-}" && -d "$_BUNDLE_WORKDIR" ]]; then
        rm -rf "$_BUNDLE_WORKDIR"
    fi
    if [[ ${#_TRACKED_TMP_FILES[@]} -gt 0 ]]; then
        local tf
        for tf in "${_TRACKED_TMP_FILES[@]}"; do
            [[ -f "$tf" ]] && rm -f "$tf"
        done
        _TRACKED_TMP_FILES=()
    fi
    [[ "$code" -ne 0 ]] && log_error "Setup interrupted with exit code $code." || true
}
trap '_cleanup $?' EXIT
trap '_cleanup 130; trap - INT;  kill -INT  "$$"' INT
trap '_cleanup 143; trap - TERM; kill -TERM "$$"' TERM

# ---------------------------------------------------------------------------
# Sudo privilege management
# ---------------------------------------------------------------------------
_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

_acquire_sudo() {
    local target_pm="${1:-package manager}"
    [[ "$(id -u)" -eq 0 ]] && return 0
    [[ "$target_pm" == "unknown" ]] && return 0
    [[ "$DRY_RUN" == true ]] && return 0

    if [[ -n "${SUDO_PID:-}" ]] && kill -0 "$SUDO_PID" 2>/dev/null; then
        return 0
    fi
    [[ -n "${SUDO_PID:-}" ]] && kill "$SUDO_PID" 2>/dev/null || true

    if sudo -n true 2>/dev/null; then
        (while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done) &
        SUDO_PID=$!
        return 0
    fi

    log_info "Requesting sudo access for ${target_pm}."
    if [[ -t 0 || -t 1 || -c /dev/tty ]] && [[ "${NON_INTERACTIVE:-false}" == false ]]; then
        local pass
        pass="$(_ui_password "[sudo] password for ${USER:-root}")"
        if [[ -n "$pass" ]]; then
            if printf '%s\n' "$pass" | sudo -S -v 2>/dev/null; then
                unset pass
                (while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done) &
                SUDO_PID=$!
                return 0
            fi
            unset pass
            log_warn "Sudo pipe authentication failed. Falling back to interactive prompt..."
        fi
    fi

    sudo -v || { log_error "Sudo authentication failed."; exit 1; }
    (while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done) &
    SUDO_PID=$!
}

# ---------------------------------------------------------------------------
# Resilient Retry & Network Helpers
# ---------------------------------------------------------------------------
_run_retry() {
    local max_attempts="${1:-$MAX_RETRIES}"
    local delay="${2:-$RETRY_DELAY}"
    local label="${3:-Command}"
    shift 3
    local attempt=1 rc=0
    while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
            local jitter=0
            [[ $delay -gt 0 ]] && jitter=$(( RANDOM % 2 ))
            local sleep_sec=$(( delay + jitter ))
            log_info "Retry attempt ${attempt}/${max_attempts} for '${label}' in ${sleep_sec}s..."
            sleep "$sleep_sec" 2>/dev/null || sleep 1
            delay=$(( delay * 2 ))
            [[ $delay -gt 30 ]] && delay=30
        fi

        rc=0
        _LAST_CMD_ERROR=""
        if [[ "${VERBOSE:-false}" == true ]]; then
            "$@" || rc=$?
        else
            _run_with_spinner "$label" "$@" || rc=$?
        fi

        if [[ $rc -eq 0 ]]; then
            return 0
        fi

        # Immediate abort on SIGINT / SIGTERM: do not waste retry loops when user interrupts
        if [[ $rc -eq 130 || $rc -eq 143 ]]; then
            return $rc
        fi

        # Fatal non-retryable exit codes: 127 (not found), 126 (not executable)
        if [[ $rc -eq 127 || $rc -eq 126 ]]; then
            return $rc
        fi

        # Timeout handling (exit 124)
        if [[ $rc -eq 124 && -z "${_LAST_CMD_ERROR:-}" ]]; then
            _LAST_CMD_ERROR="Command timed out"
        fi

        # Fatal non-retryable HTTP status codes: 404 Not Found, 401 Unauthorized
        if [[ "${_LAST_CMD_ERROR:-}" == *"404"* || "${_LAST_CMD_ERROR:-}" == *"Not Found"* || "${_LAST_CMD_ERROR:-}" == *"401 Unauthorized"* ]]; then
            return $rc
        fi

        # Rate limit 429 backoff bonus
        if [[ "${_LAST_CMD_ERROR:-}" == *"429"* || "${_LAST_CMD_ERROR:-}" == *"rate limit"* || "${_LAST_CMD_ERROR:-}" == *"Rate limit"* ]]; then
            delay=$(( delay + 5 ))
        fi

        attempt=$(( attempt + 1 ))
    done
    return $rc
}

_curl_cmd() {
    local -a args=(curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout "${NETWORK_TIMEOUT:-15}" --max-time "${INSTALL_TIMEOUT:-120}")
    local has_gh=false arg
    for arg in "$@"; do
        if [[ "$arg" == *"github.com"* || "$arg" == *"api.github.com"* ]]; then
            has_gh=true
            break
        fi
    done
    if [[ "$has_gh" == true ]]; then
        local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
        if [[ -n "$token" ]]; then
            args+=(-H "Authorization: Bearer $token")
        fi
    fi
    "${args[@]}" "$@"
}

_fetch_github_release_version() {
    local repo="$1"
    local version=""
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    local -a auth_hdr=()
    [[ -n "$token" ]] && auth_hdr=(-H "Authorization: Bearer $token")

    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local json_out=""
    json_out="$(curl --proto '=https' --tlsv1.2 -sSL --connect-timeout 5 --max-time 15 "${auth_hdr[@]}" -H "Accept: application/vnd.github+json" "$api_url" 2>/dev/null || true)"
    if [[ -n "$json_out" && "$json_out" =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
        version="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$version" || "$version" == "null" ]]; then
        local red_url
        red_url="$(curl --proto '=https' --tlsv1.2 -sSL -o /dev/null -w '%{url_effective}' --connect-timeout 5 --max-time 15 "https://github.com/${repo}/releases/latest" 2>/dev/null || true)"
        if [[ -n "$red_url" && "$red_url" == *"/releases/tag/"* ]]; then
            version="${red_url##*/}"
        fi
    fi

    if [[ -z "$version" || "$version" == "latest" ]]; then
        return 1
    fi
    printf '%s' "$version"
}

# ---------------------------------------------------------------------------
# String utilities
# ---------------------------------------------------------------------------
_trim() {
    local v="$*"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

_validate_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$ ]]
}
