# shellcheck shell=bash
# =============================================================================
#  SCRIPT & MAIN ORCHESTRATOR
# =============================================================================

# ---------------------------------------------------------------------------
# Help & Manifest Querying
# ---------------------------------------------------------------------------
_show_help() {
    printf '%s\n' "${CLR_PRIMARY}${BOLD}Dotfiles Setup${RESET}"
    printf '\n%s\n' "${BOLD}USAGE${RESET}"
    printf '    ./rigrc.sh %s[OPTIONS]%s\n' "${CLR_ACCENT}" "${RESET}"
    printf '\n%s\n' "${BOLD}OPTIONS${RESET}"
    printf '    %s %-30s %s\n' \
        "${CLR_PRIMARY}•${RESET}" '-c, --config <file>'        'Load configuration file' \
        "${CLR_PRIMARY}•${RESET}" '-y, --non-interactive'      'Run in automated non-interactive mode' \
        "${CLR_PRIMARY}•${RESET}" '-v, --verbose'               'Show verbose command output' \
        "${CLR_PRIMARY}•${RESET}" '-f, --force, --reset'        'Overwrite existing files and bypass locks' \
        "${CLR_PRIMARY}•${RESET}" '    --env <environment>'     'Override detected environment (wsl, vps, desktop)' \
        "${CLR_PRIMARY}•${RESET}" '    --skip-upgrade'          'Skip system package manager update and upgrade' \
        "${CLR_PRIMARY}•${RESET}" '    --offline'               'Skip network checks and online package downloads' \
        "${CLR_PRIMARY}•${RESET}" '    --verify-scripts'        'Prompt before running installation scripts' \
        "${CLR_PRIMARY}•${RESET}" '    --list'                  'List available packages by group' \
        "${CLR_PRIMARY}•${RESET}" '    --fmt, --format'         'Format configuration and manifest files' \
        "${CLR_PRIMARY}•${RESET}" '    --lint'                  'Validate manifest and configuration syntax' \
        "${CLR_PRIMARY}•${RESET}" '    --clean-symlinks'        'Remove broken dotfile symlinks in home directory' \
        "${CLR_PRIMARY}•${RESET}" '    --rollback [snapshot]'   'Roll back snapshot from ~/.dotfiles.bak' \
        "${CLR_PRIMARY}•${RESET}" '    --export-diagnostics'    'Export diagnostic snapshot to JSON file' \
        "${CLR_PRIMARY}•${RESET}" '    --doctor [--fix]'        'Check system environment and repair missing paths' \
        "${CLR_PRIMARY}•${RESET}" '-h, --help'                  'Show help'
    printf '\n%s\n' "${BOLD}EXAMPLES${RESET}"
    printf '    %s %s\n' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --config work.conf' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --rollback' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --doctor --fix' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --export-diagnostics' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --fmt' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --lint' \
        "${CLR_MUTED}\$${RESET}" './rigrc.sh --clean-symlinks'
    printf '\n%s\n' "${BOLD}FILES${RESET}"
    printf '    %-24s %s\n' \
        'packages/'               'Package definitions and configuration templates' \
        'packages/_groups.conf'   'Package group definitions' \
        'src/base.conf'           'Base settings and shell templates'
    exit 0
}

_list_all() {
    [[ ! -d "$PACKAGES_DIR" ]] && { log_error "Packages directory not found."; exit 1; }
    _preload_all_manifests "$PACKAGES_DIR"
    printf '\n%s %s\n\n' "${CLR_PRIMARY}${SYM_DOT}${RESET}" "${BOLD}Available Packages by Group${RESET}"
    local gname pkg
    while IFS= read -r gname; do
        [[ -z "$gname" ]] && continue
        local gdesc="$(_get_group_meta "$gname" "description")"
        local grp_active=true
        if ! _group_selected "$gname"; then
            grp_active=false
        fi

        if [[ "$grp_active" == true ]]; then
            if [[ -n "$gdesc" ]]; then
                printf '  %s %s\n' "${CLR_ACCENT}${BOLD}[${gname}]${RESET}" "${CLR_MUTED}- ${gdesc}${RESET}"
            else
                printf '  %s\n' "${CLR_ACCENT}${BOLD}[${gname}]${RESET}"
            fi
        else
            if [[ -n "$gdesc" ]]; then
                printf '  %s %s %s\n' "${CLR_MUTED}[${gname}]${RESET}" "${CLR_MUTED}- ${gdesc}${RESET}" "${CLR_MUTED}(group disabled)${RESET}"
            else
                printf '  %s %s\n' "${CLR_MUTED}[${gname}]${RESET}" "${CLR_MUTED}(group disabled)${RESET}"
            fi
        fi

        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            local is_dis=0
            if [[ "${_CONF_PKG_DISABLED["$pkg"]:-0}" -eq 1 || "$grp_active" == false ]]; then
                is_dis=1
            fi
            if [[ "$is_dis" -eq 1 ]]; then
                printf '    %s %s %s\n' "${CLR_MUTED}–${RESET}" "${CLR_MUTED}${pkg}${RESET}" "${CLR_MUTED}(excluded)${RESET}"
            else
                printf '    %s %s\n' "${CLR_PRIMARY}•${RESET}" "${BOLD}${pkg}${RESET}"
            fi
        done < <(_get_group_packages "$gname")
    done < <(_get_groups)
    exit 0
}

# ---------------------------------------------------------------------------
# Script argument parser
# ---------------------------------------------------------------------------
_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)                          CONFIG_FILE="$2"; shift 2 ;;
            --config=*)                           CONFIG_FILE="${1#*=}"; shift ;;
            --skip-upgrade)                       SKIP_UPGRADE=true; shift ;;
            -v|--verbose)                         VERBOSE=true; shift ;;
            -f|--force|--reset)                   FORCE=true; shift ;;
            --verify-scripts)                     VERIFY_SCRIPTS=true; shift ;;
            --env=*|--environment=*)             ENV="${1#*=}"; shift ;;
            --env|--environment)                 ENV="$2"; shift 2 ;;
            --offline)                            OFFLINE=true; shift ;;
            -y|--non-interactive)                 NON_INTERACTIVE=true; shift ;;
            --list|--list-groups|--list-packages) _list_all ;;
            --lint)                               _lint_manifest ;;
            --fmt|--format)                       _format_manifest ;;
            --clean-symlinks)                     _clean_broken_symlinks ;;
            --rollback=*)                         _rollback_latest_backup "${1#*=}"; exit $? ;;
            --rollback)                           
                if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
                    _rollback_latest_backup "$2"; exit $?
                else
                    _rollback_latest_backup ""; exit $?
                fi
                ;;
            --export-diagnostics)                 _export_diagnostics "${2:-dotfiles-diagnostics.json}"; exit $? ;;
            --export-diagnostics=*)               _export_diagnostics "${1#*=}"; exit $? ;;
            --doctor|--check)                     
                if [[ "${2:-}" == "--fix" || "${2:-}" == "-f" ]]; then
                    _doctor_check "--fix"
                else
                    _doctor_check
                fi
                ;;
            -h|--help) _show_help ;;
            --) shift; break ;;
            -*) log_error "Unknown option '$1'. Run './rigrc.sh --help' for usage."; exit 1 ;;
            *)  break ;;
        esac
    done
}

# =============================================================================
#  MAIN ENTRYPOINT
# =============================================================================

_main() {
    local start_time=$SECONDS
    _parse_args "$@"

    local distro; distro="$(_get_distro_name)"
    local arch; arch="$(_get_arch)"
    local pm; pm="$(_detect_pm)"
    local conds; conds="$(_get_detected_conds)"

    if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
        printf '\n%s %s\n' "${CLR_PRIMARY}${BOLD}Dotfiles Setup${RESET}" "${CLR_MUTED}v2.0${RESET}" >&2
    else
        printf '\nDotfiles Setup v2.0\n' >&2
    fi

    # ── Phase 1: Preflight ──
    _ui_phase 1 6 "Preflight"
    _check_disk_space 500 "$HOME" || exit 1

    local net_status="online"
    if ! _check_network; then
        net_status="offline/limited"
    fi
    printf '  %s (%s) · %s · %s · %s\n' "$distro" "$arch" "$pm" "$conds" "$net_status"
    [[ "$net_status" == "offline/limited" ]] && log_warn "Network appears offline or limited. Online downloads may fail."

    # ── Phase 2: Configuration ──
    _ui_phase 2 6 "Configuration"
    _preload_all_manifests "$PACKAGES_DIR"

    local cfg_name="base (built-in)"
    [[ -n "${CONFIG_FILE:-}" ]] && cfg_name="$(basename "$CONFIG_FILE")"
    printf '  Loaded configuration: %s\n' "${BOLD}${cfg_name}${RESET}"

    # ── Phase 3: Identity ──
    _ui_phase 3 6 "Identity"
    _PM="$(_detect_pm)"
    _acquire_sudo "$_PM"

    GIT_USER_NAME="${_CONF_PKG_KEYS["core/git:GIT_USER_NAME"]:-${_CONF_PKG_KEYS["git:GIT_USER_NAME"]:-${_CONF_PKG_KEYS["global:GIT_USER_NAME"]:-${GIT_USER_NAME:-}}}}"
    GIT_EMAIL="${_CONF_PKG_KEYS["core/git:GIT_EMAIL"]:-${_CONF_PKG_KEYS["git:GIT_EMAIL"]:-${_CONF_PKG_KEYS["global:GIT_EMAIL"]:-${GIT_EMAIL:-}}}}"

    local FINAL_NAME=""
    local CUR_NAME
    CUR_NAME="$(git config --global user.name 2>/dev/null || true)"
    if [[ -n "${GIT_USER_NAME:-}" ]]; then
        FINAL_NAME="$GIT_USER_NAME"
        printf '  %-24s %s\n' "Git user name" "$FINAL_NAME"
    elif [[ "$DRY_RUN" == false && "${NON_INTERACTIVE:-false}" == false && ( -t 0 || -t 1 || -c /dev/tty ) ]]; then
        FINAL_NAME="$(_ui_input "Git user name (optional)" "$CUR_NAME")"
    elif [[ -n "$CUR_NAME" ]]; then
        FINAL_NAME="$CUR_NAME"
        printf '  %-24s %s\n' "Git user name" "$FINAL_NAME"
    else
        printf '  %-24s %s\n' "Git user name" "${CLR_MUTED}(skipped)${RESET}"
    fi

    local FINAL_EMAIL=""
    local CUR_EMAIL
    CUR_EMAIL="$(git config --global user.email 2>/dev/null || true)"

    if [[ -n "${GIT_EMAIL:-}" ]]; then
        _validate_email "$GIT_EMAIL" \
            || { log_error "Invalid GIT_EMAIL format in config: '$GIT_EMAIL'. Expected name@example.com."; exit 1; }
        FINAL_EMAIL="$GIT_EMAIL"
        printf '  %-24s %s\n' "Git email" "$FINAL_EMAIL"
    elif [[ "$DRY_RUN" == false && "${NON_INTERACTIVE:-false}" == false && ( -t 0 || -t 1 || -c /dev/tty ) ]]; then
        local git_input
        git_input="$(_ui_input "Git email (optional)" "$CUR_EMAIL")"
        if [[ -n "$git_input" ]]; then
            if _validate_email "$git_input"; then
                FINAL_EMAIL="$git_input"
            else
                log_warn "Invalid email address entered. Skipping email setup."
            fi
        fi
    elif [[ -n "$CUR_EMAIL" ]]; then
        FINAL_EMAIL="$CUR_EMAIL"
        printf '  %-24s %s\n' "Git email" "$FINAL_EMAIL"
    else
        printf '  %-24s %s\n' "Git email" "${CLR_MUTED}(skipped)${RESET}"
    fi

    # ── Phase 4: System Packages ──
    _ui_phase 4 6 "System Packages"
    _upgrade_system

    # ── Phase 5: Packages ──
    _ui_phase 5 6 "Packages"
    if [[ -d "$PACKAGES_DIR" ]]; then
        install_packages "$PACKAGES_DIR"
    else
        log_warn "Packages directory not found. Skipping package installation."
    fi

    # ── Phase 6: Dotfiles ──
    _ui_phase 6 6 "Dotfiles"

    local _prof_tmpl="${_CONF_TMPL_BUF[".profile"]:-${_CONF_TMPL_BUF["profile"]:-}}"
    local _bprof_tmpl="${_CONF_TMPL_BUF[".bash_profile"]:-${_CONF_TMPL_BUF["bash_profile"]:-}}"
    local _bashrc_tmpl="${_CONF_TMPL_BUF[".bashrc"]:-${_CONF_TMPL_BUF["bashrc"]:-}}"
    local _inputrc_tmpl="${_CONF_TMPL_BUF[".inputrc"]:-${_CONF_TMPL_BUF["inputrc"]:-}}"

    _prof_tmpl="${_prof_tmpl%__TMPL_SEP__}"
    _bprof_tmpl="${_bprof_tmpl%__TMPL_SEP__}"
    _bashrc_tmpl="${_bashrc_tmpl%__TMPL_SEP__}"
    _inputrc_tmpl="${_inputrc_tmpl%__TMPL_SEP__}"

    _write_file "~/.profile" "${TEMPLATE_OVERRIDE_PROFILE:-$_prof_tmpl}" "once"
    _write_file "~/.bash_profile" "${TEMPLATE_OVERRIDE_BASH_PROFILE:-$_bprof_tmpl}" "once"
    [[ -n "$_bashrc_tmpl" ]] && _write_file "~/.bashrc" "${TEMPLATE_OVERRIDE_BASHRC:-$_bashrc_tmpl}" "once"
    [[ -n "$_inputrc_tmpl" ]] && _write_file "~/.inputrc" "${TEMPLATE_OVERRIDE_INPUTRC:-$_inputrc_tmpl}" "once"

    # Deploy and integrate shell configuration
    if [[ -d "$PACKAGES_DIR" ]]; then
        local _bashrc_snippets
        _bashrc_snippets="$(_collect_bashrc_snippets "$PACKAGES_DIR")"
        if [[ -n "$_bashrc_snippets" && -f "$DOTFILES_DIR/.bashrc" ]]; then
            local target_rc="$DOTFILES_DIR/.bashrc"
            local b_start="# ── Tool integrations start ──"
            local b_end="# ── Tool integrations end ──"
            local new_block="${b_start}"$'\n'"${_bashrc_snippets}"$'\n'"${b_end}"
            local tmp_rc
            tmp_rc="$(mktemp "${target_rc}.XXXXXX")"
            _TRACKED_TMP_FILES+=("$tmp_rc")
            awk -v block="$new_block" '
                /# ── Tool integrations start ──/ || /# ── Tool integrations/ {
                    if (!replaced) {
                        print block
                        replaced = 1
                    }
                    in_block = 1
                    next
                }
                /# ── Tool integrations end ──/ {
                    in_block = 0
                    next
                }
                !in_block { print }
                END {
                    if (!replaced) {
                        print ""
                        print block
                    }
                }
            ' "$target_rc" > "$tmp_rc"
            chmod 644 "$tmp_rc" 2>/dev/null || true
            mv "$tmp_rc" "$target_rc"
        fi
    fi

    # Stow all generated dotfiles from dotfiles repository into $HOME.
    deploy_stow

    # Git personal settings: applied AFTER stow so global options write to stowed gitconfig.
    configure_git "${FINAL_NAME:-${GIT_USER_NAME:-}}" "${FINAL_EMAIL:-${GIT_EMAIL:-}}"

    setup_github_ssh "${FINAL_EMAIL:-${GIT_EMAIL:-}}"

    if _is_wsl && [[ -f "$SCRIPT_DIR/wsl.conf" ]]; then
        deploy_wsl_conf
    fi

    if [[ -n "${POST_INSTALL_HOOK:-}" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_action "Would run post-install hook: ${POST_INSTALL_HOOK}"
        else
            log_info "Running post-install hook: ${POST_INSTALL_HOOK}"
            _run_script "$POST_INSTALL_HOOK" || log_warn "Post-install hook failed."
        fi
    fi

    local total_elapsed=$(( SECONDS - start_time ))
    _ui_render_summary "$total_elapsed" "${_INSTALLED_PACKAGES_COUNT:-0}" "${BACKUP_COUNT:-0}"
}
