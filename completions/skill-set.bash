# Bash completion for skill-set.

_skill_set_compgen() {
  local words cur_word item
  words="$1"
  cur_word="$2"
  COMPREPLY=()
  while IFS= read -r item; do
    [ -n "$item" ] && COMPREPLY+=("$item")
  done < <(compgen -W "$words" -- "$cur_word")
}

_skill_set_completion() {
  local cur commands sets sub typed s remaining stack
  COMPREPLY=()
  compopt +o default +o bashdefault 2>/dev/null || true

  cur="${COMP_WORDS[COMP_CWORD]}"
  commands="load add remove unload list current sync doctor --help"

  sets="$(skill-set list 2>/dev/null || true)"

  if [ "$COMP_CWORD" -eq 1 ]; then
    _skill_set_compgen "$commands $sets" "$cur"
    return 0
  fi

  sub="${COMP_WORDS[1]}"
  case "$sub" in
    load | add | remove | unload | list | current | sync | doctor | --help | -h | help) ;;
    *) sub="load" ;;
  esac

  case "$sub" in
    load)
      typed=" "
      local i
      for ((i = 2; i < COMP_CWORD; i++)); do
        typed+="${COMP_WORDS[i]} "
      done
      remaining=""
      for s in $sets; do
        case "$typed" in
          *" $s "*) ;;
          *) remaining+="$s " ;;
        esac
      done
      _skill_set_compgen "$remaining" "$cur"
      ;;
    add)
      stack="$(skill-set current 2>/dev/null | grep -v '^(none)$' || true)"
      remaining=""
      for s in $sets; do
        if printf '%s\n' "$stack" | grep -Fxq "$s"; then
          continue
        fi
        remaining+="$s "
      done
      _skill_set_compgen "$remaining" "$cur"
      ;;
    remove)
      stack="$(skill-set current 2>/dev/null | grep -v '^(none)$' || true)"
      _skill_set_compgen "$stack" "$cur"
      ;;
    *)
      COMPREPLY=()
      return 0
      ;;
  esac
}

complete -F _skill_set_completion skill-set
complete -F _skill_set_completion sklset
