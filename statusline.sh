#!/usr/bin/env bash

if [ -t 0 ]; then
  status_json=""
else
  status_json="$(cat 2>/dev/null || true)"
fi

handy_hint="space hold to record"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/copilot-statusline"
esc="$(printf '\033')"
reset="${esc}[0m"
dim="${esc}[2m"
separator=" ${dim}·${reset} "
c_refresh="${dim}"
c_handy="${esc}[38;5;196m"
c_azure="${esc}[38;5;208m"
c_github="${esc}[38;5;226m"
c_tokens="${esc}[38;5;201m"
c_agents="${esc}[38;5;46m"
c_squad="${esc}[38;5;33m"
c_openspec="${esc}[38;5;99m"
c_speckit="${esc}[38;5;129m"

project_dir="$PWD"
if [ -n "$status_json" ] && command -v jq >/dev/null 2>&1; then
  json_project_dir="$(
    printf '%s' "$status_json" | jq -r '
      def folder_path:
        if type == "string" then .
        elif type == "object" then (.path? // .uri? // empty)
        else empty end;

      [
        .cwd?,
        .currentWorkingDirectory?,
        .workingDirectory?,
        .workspaceFolder?,
        .workspaceRoot?,
        (.workspaceFolders?[0]? | folder_path),
        (.workspace_folders?[0]? | folder_path)
      ]
      | map(select(type == "string" and length > 0))
      | .[0] // empty
    ' 2>/dev/null || true
  )"
  if [ -n "$json_project_dir" ] && [ -d "$json_project_dir" ]; then
    project_dir="$json_project_dir"
  fi
fi

find_up() {
  local dir="$1"
  local marker="$2"

  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -e "$dir/$marker" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  return 1
}

file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

cache_key() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s:%s\n' "$1" "$2" | shasum | awk '{print $1}'
  elif command -v sha1sum >/dev/null 2>&1; then
    printf '%s:%s\n' "$1" "$2" | sha1sum | awk '{print $1}'
  else
    printf '%s:%s\n' "$1" "$2" | cksum | awk '{print $1}'
  fi
}

run_with_timeout() {
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift @ARGV; exec @ARGV' 2 "$@"
  else
    "$@"
  fi
}

cached_command() {
  local key="$1"
  local ttl="$2"
  local dir="$3"
  shift 3

  mkdir -p "$cache_dir" 2>/dev/null || true
  local file="$cache_dir/$key"
  local now
  local mtime
  now="$(date +%s)"

  if [ -s "$file" ]; then
    mtime="$(file_mtime "$file")"
    if [ $((now - mtime)) -lt "$ttl" ]; then
      cat "$file"
      return 0
    fi
  fi

  local output
  output="$(
    cd "$dir" 2>/dev/null &&
      run_with_timeout "$@" 2>&1 |
        tr -d '\r' |
        sed -n '1,80p'
  )" || true

  printf '%s' "$output" >"$file" 2>/dev/null || true
  printf '%s' "$output"
}

count_tasks() {
  local tasks_file="$1"
  local label="$2"
  local total
  local done

  [ -f "$tasks_file" ] || return 1

  total="$(grep -E '^[[:space:]]*- \[[ xX]\]' "$tasks_file" 2>/dev/null | wc -l | tr -d ' ')"
  done="$(grep -E '^[[:space:]]*- \[[xX]\]' "$tasks_file" 2>/dev/null | wc -l | tr -d ' ')"

  if [ "${total:-0}" -gt 0 ]; then
    printf '%s: %s/%s tasks\n' "$label" "${done:-0}" "$total"
    return 0
  fi

  return 1
}

latest_child_dir() {
  local parent="$1"

  [ -d "$parent" ] || return 1

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    while IFS= read -r dir; do
      printf '%s\t%s\n' "$(file_mtime "$dir")" "$dir"
    done |
    sort -rn |
    head -1 |
    cut -f2-
}

short_text() {
  local text="$1"
  local max="${2:-36}"

  if [ "${#text}" -gt "$max" ]; then
    printf '%s...\n' "${text:0:$((max - 3))}"
  else
    printf '%s\n' "$text"
  fi
}

paint() {
  local color="$1"
  local text="$2"

  [ -n "$text" ] || return 0
  printf '%s%s%s\n' "$color" "$text" "$reset"
}

refresh_status() {
  printf '↻ %s\n' "$(date '+%H:%M:%S')"
}

azure_status() {
  command -v az >/dev/null 2>&1 || return 0

  local output
  local user

  output="$(cached_command azure-account-v3 60 "$HOME" az account show --query "user.name" -o tsv)"
  user="$(printf '%s\n' "$output" | sed -n '1p')"

  [ -n "$user" ] || return 0
  printf 'az: %s\n' "$(short_text "$user" 32)"
}

github_status() {
  command -v gh >/dev/null 2>&1 || return 0

  local output
  local account=""
  local line

  output="$(cached_command github-auth 60 "$HOME" gh auth status)"

  while IFS= read -r line; do
    case "$line" in
      *"Logged in to github.com account "*)
        account="${line#*account }"
        account="${account%% *}"
        ;;
      *"Active account: true"*)
        [ -n "$account" ] && break
        ;;
    esac
  done <<EOF
$output
EOF

  [ -n "$account" ] || return 0
  printf 'gh: %s\n' "$account"
}

token_usage_status() {
  command -v ai-engineering-fluency >/dev/null 2>&1 || return 0

  local output
  local tokens

  output="$(cached_command ai-fluency-usage-v1 300 "$HOME" ai-engineering-fluency usage)"
  tokens="$(
    printf '%s\n' "$output" |
      awk 'BEGIN{in30=0} /Last 30 Days/{in30=1; next} in30 && /Total tokens:/ {print $NF; exit}'
  )"

  [ -n "$tokens" ] || return 0
  printf 'tokens<30d: %s\n' "$tokens"
}

subtask_status="$(
  if [ -n "$status_json" ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$status_json" | jq -r '
      def active_state:
        tostring
        | ascii_downcase
        | test("running|starting|pending|queued|in[_ -]?progress|spawning|active");

      def agentish:
        has("agent_id")
        or has("agentId")
        or has("agent_type")
        or has("agentType")
        or ((.type? // .kind? // .category? // "" | tostring) | test("agent|subagent|sidekick"; "i"));

      def agent_path($path):
        $path
        | map(tostring)
        | join(".")
        | test("agent|subagent|sidekick"; "i");

      def short:
        tostring
        | if length > 40 then .[0:37] + "..." else . end;

      (
        [
        paths(objects) as $path
        | getpath($path)
        | select(agentish or agent_path($path))
        | select((.status? // .state? // .phase? // "active") | active_state)
        | (
            .agent_id
            // .agentId
            // .id
            // .name
            // .title
            // .description
            // .agent_type
            // .agentType
            // "agent"
            | short
          )
        ]
        | unique
        | length
      ) as $count
      | if $count == 0 then empty
        elif $count == 1 then "subtasks: 1 running"
        else "subtasks: \($count) running"
        end
    ' 2>/dev/null || true
  fi
)"

squad_status() {
  local root
  root="$(find_up "$project_dir" ".squad" || find_up "$project_dir" ".ai-team" || true)"
  [ -n "$root" ] || return 0

  if ! command -v squad >/dev/null 2>&1; then
    printf 'squad: active\n'
    return 0
  fi

  local output
  local active
  output="$(cached_command "$(cache_key squad "$root")" 0 "$root" squad status)"
  active="$(
    printf '%s\n' "$output" |
      awk -F: '/Active squad:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}'
  )"

  if [ -n "$active" ] && [ "$active" != "none" ]; then
    printf 'squad: %s\n' "$active"
  else
    printf 'squad: active\n'
  fi
}

openspec_status() {
  local root
  root="$(find_up "$project_dir" "openspec" || find_up "$project_dir" ".openspec" || true)"
  [ -n "$root" ] || return 0

  if ! command -v openspec >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf 'openspec: enabled\n'
    return 0
  fi

  local output
  local summary

  output="$(
    cd "$root" 2>/dev/null &&
      run_with_timeout openspec list --json 2>/dev/null
  )" || true

  summary="$(
    printf '%s' "$output" | jq -r '
      def pct($done; $total):
        if ($total // 0) <= 0 then "0%"
        else (((($done // 0) * 100 / $total) | floor | tostring) + "%")
        end;

      def short:
        tostring
        | if length > 16 then .[0:13] + "..." else . end;

      (.changes // [])
      | map(select((.status // "") != "archived"))
      | if length == 0 then "openspec: 0 changes"
        else
          "openspec: "
          + (
            .[:3]
            | map(
                (.name // .id // "change" | short)
                + " "
                + pct(.completedTasks; .totalTasks)
              )
            | join(", ")
          )
          + (if length > 3 then " +" + ((length - 3) | tostring) else "" end)
        end
    ' 2>/dev/null || true
  )"

  if [ -n "$summary" ]; then
    printf '%s\n' "$summary"
  else
    printf 'openspec: enabled\n'
  fi
}

speckit_status() {
  local root=""
  local dir="$project_dir"

  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/.specify" ] ||
      find "$dir/specs" -mindepth 2 -maxdepth 2 \( -name 'spec.md' -o -name 'plan.md' -o -name 'tasks.md' \) -print -quit 2>/dev/null | grep -q .; then
      root="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done

  [ -n "$root" ] || return 0

  local feature_dir
  feature_dir="$(latest_child_dir "$root/specs" || true)"

  if [ -n "$feature_dir" ]; then
    count_tasks "$feature_dir/tasks.md" "spec-kit" && return 0

    if [ -f "$feature_dir/plan.md" ]; then
      printf 'spec-kit: plan\n'
      return 0
    fi

    if [ -f "$feature_dir/spec.md" ]; then
      printf 'spec-kit: spec\n'
      return 0
    fi
  fi

  printf 'spec-kit: active\n'
}

join_segments() {
  local output=""
  local segment

  for segment in "$@"; do
    [ -n "$segment" ] || continue
    if [ -n "$output" ]; then
      output="${output}${separator}${segment}"
    else
      output="$segment"
    fi
  done

  printf '%s\n' "$output"
}

join_segments \
  "$(paint "$c_handy" "$handy_hint")" \
  "$(paint "$c_refresh" "$(refresh_status)")" \
  "$(paint "$c_azure" "$(azure_status)")" \
  "$(paint "$c_github" "$(github_status)")" \
  "$(paint "$c_tokens" "$(token_usage_status)")" \
  "$(paint "$c_agents" "$subtask_status")" \
  "$(paint "$c_squad" "$(squad_status)")" \
  "$(paint "$c_openspec" "$(openspec_status)")" \
  "$(paint "$c_speckit" "$(speckit_status)")"
