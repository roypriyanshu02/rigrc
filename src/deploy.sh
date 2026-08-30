# shellcheck shell=bash
# =============================================================================
#  DEPLOYMENT MODULES (Atomic Writes, Templates, Stow, Rollback)
# =============================================================================

# ---------------------------------------------------------------------------
# Atomic File Writer & Backup Manager
# ---------------------------------------------------------------------------
_backup_file() {
    local dest="$1" rel="$2"
    _get_backup_dir
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$dest" "$BACKUP_DIR/$rel"
    BACKUP_COUNT=$((BACKUP_COUNT + 1))
}

_write_file() {
    local target="$1" content="$2" flags="${3:-}"
    local dest="${target/#\~/$HOME}"

    # Ensure single trailing newline if missing while preserving template formatting
    if [[ -n "$content" && "$content" != *$'\n' ]]; then
        content+=$'\n'
    fi

    # System-scoped target path (e.g. /etc/sysctl.d/...) - direct root write bypassing stow
    if [[ "$dest" != "$HOME/"* && "$dest" != "$HOME" ]]; then
        if [[ "$flags" == *once* && "$FORCE" != true ]] && [[ -f "$dest" ]]; then
            log_info "Already exists, skipping: ${dest}"
            return
        fi
        if [[ -f "$dest" ]] && printf '%s' "$content" | cmp -s - "$dest"; then
            log_info "Up to date: ${dest}"
            return
        fi
        if [[ "$DRY_RUN" == true ]]; then
            log_action "Would write system file: ${dest}"
        else
            local tmp
            tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles_sys_XXXXXX")"
            _TRACKED_TMP_FILES+=("$tmp")
            printf '%s' "$content" > "$tmp"
            _sudo mkdir -p "$(dirname "$dest")"
            _sudo cp "$tmp" "$dest"
            _sudo chmod 644 "$dest"
            rm -f "$tmp"
            log_success "Wrote system file: ${dest}"
        fi
        return
    fi

    local rel="${dest#"$HOME/"}"
    local stow_src="$DOTFILES_DIR/$rel"

    # "once": create only if absent in dotfiles directory (bypassed if FORCE=true)
    if [[ "$flags" == *once* && "$FORCE" != true && -f "$stow_src" ]]; then
        log_info "Already exists, skipping: ${rel}"
    elif [[ -f "$stow_src" ]] && printf '%s' "$content" | cmp -s - "$stow_src"; then
        log_info "Up to date: ${rel}"
    else
        if [[ "$DRY_RUN" == true ]]; then
            log_action "Would write template: ${target}"
        else
            mkdir -p "$(dirname "$stow_src")"
            local tmp
            tmp="$(mktemp "${stow_src}.XXXXXX")"
            _TRACKED_TMP_FILES+=("$tmp")
            printf '%s' "$content" > "$tmp"
            chmod 644 "$tmp" 2>/dev/null || true
            mv "$tmp" "$stow_src"
            printf '%s%s %s\n' "${LOG_INDENT:-    }" "${CLR_MUTED}↳${RESET}" "${CLR_MUTED}${target}${RESET}" >&2
        fi
    fi

    # Back up and clear pre-existing regular file in $HOME before stow symlinks it
    if [[ -e "$dest" || -L "$dest" ]]; then
        local real_dest real_stow
        real_dest="$(readlink -f "$dest" 2>/dev/null || true)"
        real_stow="$(readlink -f "$stow_src" 2>/dev/null || true)"
        if [[ -n "$real_stow" && "$real_dest" != "$real_stow" ]]; then
            if [[ -f "$dest" && ! -L "$dest" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_action "Would back up existing file: ${target}"
                else
                    _backup_file "$dest" "$rel"
                    log_action "Backed up existing file: ${target}"
                fi
            elif [[ -L "$dest" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_action "Would remove obsolete symlink: ${target}"
                else
                    rm -f "$dest"
                fi
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Rollback Engine: Restores timestamped backup snapshots
# ---------------------------------------------------------------------------
_rollback_latest_backup() {
    local target_snap="${1:-}"
    local bak_root="$HOME/.dotfiles.bak"
    if [[ ! -d "$bak_root" ]]; then
        log_error "No backup directory found at ${bak_root}."
        return 1
    fi

    local snapshots=()
    local sdir
    while IFS= read -r sdir; do
        [[ -n "$sdir" && -d "$sdir" ]] && snapshots+=("$sdir")
    done < <(find "$bak_root" -mindepth 1 -maxdepth 1 -type d | sort -r)

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log_error "No backup snapshots found in ${bak_root}."
        return 1
    fi

    local chosen_bak=""
    if [[ -n "$target_snap" ]]; then
        if [[ -d "$bak_root/$target_snap" ]]; then
            chosen_bak="$bak_root/$target_snap"
        elif [[ -d "$target_snap" ]]; then
            chosen_bak="$target_snap"
        else
            log_error "Specified snapshot '$target_snap' does not exist."
            return 1
        fi
    elif [[ ${#snapshots[@]} -eq 1 || "${NON_INTERACTIVE:-false}" == true || ! -t 0 ]]; then
        chosen_bak="${snapshots[0]}"
    else
        local snap_names=()
        local s
        for s in "${snapshots[@]}"; do
            snap_names+=("$(basename "$s")")
        done
        local sel
        sel="$(_ui_select "Select backup snapshot to restore:" "${snap_names[@]}")"
        chosen_bak="$bak_root/$sel"
    fi

    log_info "Rolling back from snapshot: $(basename "$chosen_bak")"
    local restored_count=0
    local bak_file
    while IFS= read -r -d '' bak_file; do
        local rel="${bak_file#"$chosen_bak/"}"
        [[ "$rel" == ".backup_manifest.json" ]] && continue
        if [[ "$rel" == *".."* || "$rel" == /* ]]; then
            log_warn "Skipping invalid snapshot file path: ${rel}"
            continue
        fi
        local dest="$HOME/$rel"
        mkdir -p "$(dirname "$dest")"
        cp -a "$bak_file" "$dest"
        log_success "Restored: ~/${rel}"
        restored_count=$((restored_count + 1))
    done < <(find "$chosen_bak" -type f -print0)

    if [[ $restored_count -eq 0 ]]; then
        log_warn "Backup snapshot was empty."
        return 0
    fi
    log_success "Rollback complete. Restored ${restored_count} file(s) from $(basename "$chosen_bak")."
    return 0
}

deploy_package_templates() {
    local conf_file="$1"
    [[ ! -f "$conf_file" ]] && return 0
    local LOG_INDENT="${LOG_INDENT:-    }"
    local SPINNER_INDENT="${SPINNER_INDENT:-    }"
    _preload_manifest_file "$conf_file"

    local tmpl_all="${_CONF_TEMPLATES["$conf_file"]:-}"
    [[ -z "$tmpl_all" ]] && return 0

    local rest="$tmpl_all"
    while [[ -n "$rest" ]]; do
        local template_content=""
        if [[ "$rest" == *"__TMPL_SEP__"* ]]; then
            template_content="${rest%%__TMPL_SEP__*}"
            rest="${rest#*__TMPL_SEP__}"
        else
            template_content="$rest"
            rest=""
        fi
        [[ -z "$template_content" ]] && continue

        local first_line tmpl_target="" tmpl_flags="" content=""
        first_line="${template_content%%$'\n'*}"
        if [[ "$first_line" =~ ^#[[:space:]]*target:[[:space:]]*([^[:space:]]+)([[:space:]]+flags:(.+))? ]]; then
            tmpl_target="${BASH_REMATCH[1]}"
            [[ -n "${BASH_REMATCH[3]:-}" ]] && tmpl_flags="${BASH_REMATCH[3]}"
            content="${template_content#*$'\n'}"
        else
            content="$template_content"
        fi

        if [[ -n "$tmpl_target" && "${_CONF_TMPL_DIS["$tmpl_target"]:-0}" -eq 1 ]]; then
            continue
        fi

        # Check if user config has an explicit override for this template target
        if [[ -n "$tmpl_target" && -n "${_CONF_TMPL_BUF["$tmpl_target"]:-}" ]]; then
            local raw_custom="${_CONF_TMPL_BUF["$tmpl_target"]}"
            while [[ -n "$raw_custom" ]]; do
                local cur_cblock=""
                if [[ "$raw_custom" == *"__TMPL_SEP__"* ]]; then
                    cur_cblock="${raw_custom%%__TMPL_SEP__*}"
                    raw_custom="${raw_custom#*__TMPL_SEP__}"
                else
                    cur_cblock="$raw_custom"
                    raw_custom=""
                fi
                [[ -z "$cur_cblock" ]] && continue
                local cur_cfirst="${cur_cblock%%$'\n'*}"
                if [[ "$cur_cfirst" =~ flags:.*override ]]; then
                    if [[ "$cur_cfirst" =~ ^#[[:space:]]*target:[[:space:]]*([^[:space:]]+)([[:space:]]+flags:(.+))? ]]; then
                        tmpl_target="${BASH_REMATCH[1]}"
                        [[ -n "${BASH_REMATCH[3]:-}" ]] && tmpl_flags="${BASH_REMATCH[3]}"
                        content="${cur_cblock#*$'\n'}"
                    fi
                    break
                fi
            done
        fi

        local tmpl_cond=""
        if [[ "$tmpl_flags" =~ cond=([^[:space:]]+) || "$tmpl_flags" =~ cond:([^[:space:]]+) ]]; then
            tmpl_cond="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$tmpl_cond" ]]; then
            if ! _eval_cond "$tmpl_cond"; then
                log_info "Skipping template (unmet condition $tmpl_cond): $tmpl_target"
                continue
            fi
        fi

        local pkg_name="${conf_file##*/}"; pkg_name="${pkg_name%.conf}"
        local var_name="TEMPLATE_OVERRIDE_${pkg_name^^}"
        var_name="${var_name//-/_}"
        var_name="${var_name//./_}"
        local override_content="${!var_name:-}"
        [[ -n "$override_content" ]] && content="$override_content"

        if [[ -n "$tmpl_target" ]]; then
            local write_flags="append"
            [[ "$tmpl_flags" == *"once"* ]] && write_flags="once"
            [[ "$tmpl_flags" == *"override"* ]] && write_flags="override"
            _write_file "$tmpl_target" "$content" "$write_flags"

            local post_hook=""
            if [[ "$tmpl_flags" =~ post=\"([^\"]+)\" ]]; then
                post_hook="${BASH_REMATCH[1]}"
            elif [[ "$tmpl_flags" =~ post=([^:]+) ]]; then
                post_hook="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$post_hook" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_action "Would run template post hook: $post_hook"
                else
                    _run_script "$post_hook" "Running template hook: $tmpl_target" || log_warn "Template hook failed for '$tmpl_target'."
                fi
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# Deploy Standalone & Global Templates from User Config
# ---------------------------------------------------------------------------
deploy_global_templates() {
    local global_tmpls="${_CONF_TMPL_BUF["global"]:-}"
    [[ -z "$global_tmpls" ]] && return 0
    local rest="$global_tmpls"
    while [[ -n "$rest" ]]; do
        local template_content=""
        if [[ "$rest" == *"__TMPL_SEP__"* ]]; then
            template_content="${rest%%__TMPL_SEP__*}"
            rest="${rest#*__TMPL_SEP__}"
        else
            template_content="$rest"
            rest=""
        fi
        [[ -z "$template_content" ]] && continue

        local first_line tmpl_target="" tmpl_flags="" content=""
        first_line="${template_content%%$'\n'*}"
        if [[ "$first_line" =~ ^#[[:space:]]*target:[[:space:]]*([^[:space:]]+)([[:space:]]+flags:(.+))? ]]; then
            tmpl_target="${BASH_REMATCH[1]}"
            [[ -n "${BASH_REMATCH[3]:-}" ]] && tmpl_flags="${BASH_REMATCH[3]}"
            content="${template_content#*$'\n'}"
        else
            content="$template_content"
        fi

        case "$tmpl_target" in
            .profile|~/.profile|.bash_profile|~/.bash_profile|.bashrc|~/.bashrc|.inputrc|~/.inputrc)
                continue ;;
        esac

        if [[ -n "$tmpl_target" && "${_CONF_TMPL_DIS["$tmpl_target"]:-0}" -eq 1 ]]; then
            continue
        fi

        local tmpl_cond=""
        if [[ "$tmpl_flags" =~ cond=([^[:space:]]+) || "$tmpl_flags" =~ cond:([^[:space:]]+) ]]; then
            tmpl_cond="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$tmpl_cond" ]]; then
            if ! _eval_cond "$tmpl_cond"; then
                log_info "Skipping template (unmet condition $tmpl_cond): $tmpl_target"
                continue
            fi
        fi

        if [[ -n "$tmpl_target" ]]; then
            local write_flags="append"
            [[ "$tmpl_flags" == *"once"* ]] && write_flags="once"
            [[ "$tmpl_flags" == *"override"* ]] && write_flags="override"
            _write_file "$tmpl_target" "$content" "$write_flags"
        fi
    done
}

_ensure_stow_ignore() {
    [[ "$DRY_RUN" == true ]] && return
    local ignore_file="$DOTFILES_DIR/.stow-local-ignore"
    if [[ ! -f "$ignore_file" ]]; then
        mkdir -p "$DOTFILES_DIR"
        cat << 'EOF' > "$ignore_file"
^\.git.*$
^README.*$
^LICENSE.*$
EOF
    fi
}

# ---------------------------------------------------------------------------
# Stow deployment: symlink dotfile configs from $DOTFILES_DIR into $HOME
# ---------------------------------------------------------------------------
deploy_stow() {
    mkdir -p "$DOTFILES_DIR"
    _ensure_stow_ignore

    # Clean up and back up any pre-existing unlinked regular files in $HOME before stowing
    local file dest rel real_dest real_stow
    while IFS= read -r -d '' file; do
        rel="${file#"$DOTFILES_DIR/"}"
        [[ "$rel" == ".git"* || "$rel" == ".stow-local-ignore" ]] && continue
        dest="$HOME/$rel"
        if [[ -e "$dest" || -L "$dest" ]]; then
            # Merge dynamically added tools (e.g. from mise use -g) before backup and symlinking
            if [[ "$rel" == ".config/mise/config.toml" && -f "$dest" && ! -L "$dest" && -f "$file" ]]; then
                if grep -q "^\[tools\]" "$dest" && ! grep -q "^\[tools\]" "$file"; then
                    awk '/^\[tools\]/{flag=1} flag{print}' "$dest" >> "$file"
                fi
            fi

            real_dest="$(readlink -f "$dest" 2>/dev/null || true)"
            real_stow="$(readlink -f "$file" 2>/dev/null || true)"
            if [[ -n "$real_stow" && "$real_dest" != "$real_stow" ]]; then
                if [[ -f "$dest" && ! -L "$dest" ]]; then
                    if [[ "$DRY_RUN" == true ]]; then
                        log_action "Would back up existing file before stow: ${rel}"
                    else
                        _backup_file "$dest" "$rel"
                        log_action "Backed up existing file before stow: ${rel}"
                    fi
                elif [[ -L "$dest" ]]; then
                    if [[ "$DRY_RUN" == true ]]; then
                        log_action "Would remove obsolete symlink before stow: ${rel}"
                    else
                        rm -f "$dest"
                    fi
                fi
            fi
        fi
    done < <(find "$DOTFILES_DIR" -type f -print0)

    _deploy_direct_symlinks() {
        local file dest ignore_patterns=()
        if [[ -f "$DOTFILES_DIR/.stow-local-ignore" ]]; then
            local p
            while IFS= read -r p || [[ -n "$p" ]]; do
                p="${p#"${p%%[![:space:]]*}"}"
                p="${p%"${p##*[![:space:]]}"}"
                [[ -z "$p" || "$p" == '#'* ]] && continue
                ignore_patterns+=("$p")
            done < "$DOTFILES_DIR/.stow-local-ignore"
        fi

        while IFS= read -r -d '' file; do
            local rel="${file#"$DOTFILES_DIR/"}"
            [[ "$rel" == ".git"* || "$rel" == ".stow-local-ignore" ]] && continue
            local skip=false pat
            for pat in "${ignore_patterns[@]}"; do
                if [[ "$rel" =~ $pat ]]; then
                    skip=true
                    break
                fi
            done
            [[ "$skip" == true ]] && continue

            dest="$HOME/$rel"
            if [[ "$DRY_RUN" == true ]]; then
                log_action "Would link $file to $dest"
            else
                mkdir -p "$(dirname "$dest")"
                ln -sf "$file" "$dest"
            fi
        done < <(find "$DOTFILES_DIR" -type f -print0)
        log_success "Linked dotfiles directly."
    }

    if command -v stow >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == true ]]; then
            log_action "Would link dotfiles with GNU Stow"
        else
            if stow -R --target="$HOME" --dir="$DOTFILES_DIR" . 2>/dev/null; then
                log_success "Linked dotfiles with GNU Stow."
            else
                log_warn "GNU Stow encountered conflicts; falling back to direct symlinking..."
                _deploy_direct_symlinks
            fi
        fi
    else
        _deploy_direct_symlinks
    fi
}

# =============================================================================
#  SYSTEM & TOOL INTEGRATIONS (Git, SSH, WSL)
# =============================================================================

configure_git() {
    local name="${1:-${GIT_USER_NAME:-}}"
    local email="${2:-}"

    _git_set() {
        local key="$1" val="$2"
        if [[ "$DRY_RUN" == true ]]; then
            log_action "Would set git ${key}: ${val}"
        else
            git config --global "$key" "$val" || log_warn "Failed to set git config '${key}'."
        fi
    }

    _git_set_if_changed() {
        local key="$1" val="$2"
        [[ -z "$val" ]] && return 0
        local cur_val
        cur_val="$(git config --global "$key" 2>/dev/null || true)"
        if [[ "$val" != "$cur_val" ]]; then
            _git_set "$key" "$val"
            [[ "$DRY_RUN" != true ]] && log_success "Set git ${key}: ${val}"
        else
            log_info "Git ${key} already set: ${val}"
        fi
    }

    _git_set_if_changed "user.name" "$name"
    _git_set_if_changed "user.email" "$email"
    [[ -n "${GIT_DEFAULT_BRANCH:-}" ]] && _git_set "init.defaultBranch" "$GIT_DEFAULT_BRANCH"
    [[ -n "${GIT_EDITOR:-}" ]] && _git_set "core.editor" "$GIT_EDITOR"

    if [[ -n "${GIT_SIGNING_KEY:-}" ]]; then
        _git_set "user.signingKey" "$GIT_SIGNING_KEY"
        _git_set "commit.gpgSign" "true"
        [[ "$DRY_RUN" != true ]] && log_info "Git commit signing enabled: ${GIT_SIGNING_KEY}"
    fi
}

setup_github_ssh() {
    local email="${1:-}"

    local ssh_dir="$HOME/.ssh"
    local key_path="$ssh_dir/id_ed25519"
    local pub_key_path="${key_path}.pub"
    local key_to_use=""

    if [[ "$DRY_RUN" == true ]]; then
        log_action "Would check existing SSH keys in ${ssh_dir}"
        log_action "Would generate Ed25519 SSH key for '${email:-user@example.com}'"
        log_action "Would add github.com host key to ${ssh_dir}/known_hosts"
        log_action "Would upload public SSH key to GitHub via gh CLI"
        return 0
    fi

    mkdir -p -m 700 "$ssh_dir"

    local existing_key=""
    local k
    for k in "$ssh_dir/id_ed25519" "$ssh_dir/id_rsa" "$ssh_dir/id_ecdsa"; do
        if [[ -f "$k" && -f "${k}.pub" ]]; then
            existing_key="$k"
            break
        fi
    done

    if [[ -n "$existing_key" ]]; then
        log_info "Found existing SSH key: ${existing_key}"
        if _prompt_confirm "Use existing SSH key (${existing_key}) for GitHub?" true; then
            key_to_use="$existing_key"
        fi
    fi

    if [[ -z "$key_to_use" ]]; then
        if [[ -z "$email" ]]; then
            _WARNING_MESSAGES+=("Git email is not configured. SSH key generation was skipped.
    Configure it with: git config --global user.email \"you@example.com\"")
            return 0
        fi

        if [[ -f "$key_path" ]]; then
            log_warn "SSH key '${key_path}' already exists. Skipping key generation."
            key_to_use="$key_path"
        elif _prompt_confirm "Generate new Ed25519 SSH key for GitHub (${email})?" true; then
            ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N "" || {
                log_error "Failed to generate SSH key."
                return 1
            }
            chmod 600 "$key_path"
            chmod 644 "$pub_key_path"
            log_success "Generated SSH key: ${key_path}"
            key_to_use="$key_path"
        else
            log_info "Skipped SSH key generation."
            return 0
        fi
    fi

    if [[ -n "$key_to_use" && -f "$key_to_use" ]]; then
        if command -v ssh-add >/dev/null 2>&1; then
            if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
                eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
                [[ -n "${SSH_AGENT_PID:-}" ]] && _TRACKED_CHILD_PIDS+=("$SSH_AGENT_PID")
            fi
            ssh-add "$key_to_use" >/dev/null 2>&1 || true
        fi
    fi

    if command -v ssh-keyscan >/dev/null 2>&1 && ! ssh-keygen -F github.com -f "$ssh_dir/known_hosts" >/dev/null 2>&1; then
        log_info "Adding github.com to ${ssh_dir}/known_hosts"
        touch "$ssh_dir/known_hosts" && chmod 600 "$ssh_dir/known_hosts"
        ssh-keyscan -t ed25519,rsa github.com 2>/dev/null >> "$ssh_dir/known_hosts" || true
    fi

    if [[ -n "$key_to_use" && -f "${key_to_use}.pub" ]]; then
        local pub_key="${key_to_use}.pub"
        if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
            if _prompt_confirm "Upload public SSH key to your GitHub account using gh CLI?" true; then
                local title
                title="$(hostname -s 2>/dev/null || echo "dotfiles-key")"
                if gh ssh-key add "$pub_key" --title "$title"; then
                    log_success "SSH public key uploaded to GitHub."
                else
                    log_warn "Could not upload SSH key via gh CLI (key may already exist on GitHub)."
                fi
            fi
        else
            log_info "GitHub CLI (gh) not authenticated. Add key manually:"
            printf '\n  ┌─ %s ──────────────────────────────────────────\n' "${BOLD}Public SSH Key${RESET}"
            printf '  │  %s%s%s\n' "${CLR_ACCENT}" "$(cat "$pub_key")" "${RESET}"
            printf '  └────────────────────────────────────────────────────────\n'
            printf '  Add key to GitHub: %shttps://github.com/settings/ssh/new%s\n\n' "${CLR_PRIMARY}${UNDERLINE:-}" "${RESET}"
        fi
    fi
}

deploy_wsl_conf() {
    [[ ! -f "$SCRIPT_DIR/wsl.conf" ]] && return
    if [[ "$DRY_RUN" == true ]]; then
        log_action "Would deploy wsl.conf -> /etc/wsl.conf"; return
    fi
    if [[ -f /etc/wsl.conf && ! -L /etc/wsl.conf ]]; then
        _get_backup_dir
        mkdir -p "$BACKUP_DIR/etc"
        _sudo cp /etc/wsl.conf "$BACKUP_DIR/etc/wsl.conf"
    fi
    _sudo cp "$SCRIPT_DIR/wsl.conf" /etc/wsl.conf
    _sudo chown root:root /etc/wsl.conf 2>/dev/null || true
    _sudo chmod 644 /etc/wsl.conf
    log_success "Configured /etc/wsl.conf."
}
