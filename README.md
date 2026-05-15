# skill-set

`skill-set` is a local skill management system for AI coding agents.

It organizes filesystem skills into composable named bundles. Keep shared
skills in `default` as a stable baseline, then layer task-specific sets on top
by switching which bundles are symlinked into each agent's skills directory.

Install skills the same way you would for `.agents` or `.claude`, but put them
under `~/skill-set` instead. To keep the source directory somewhere else, set
`SKILL_SETS=/path/to/skill-set`.

It manages two layers so common skills can stay loaded while task-specific
skills change:

- `default`: permanently linked skills.
- an ordered active stack of named sets. Replace it with
  `skill-set load <name...>`, append to it with `skill-set add <name>`, remove
  from it with `skill-set remove <name>`, and clear it with `skill-set unload`.

The default set is always linked first when it exists. Active sets are linked on
top of it, and a skill name can appear only once across `default` and the active
stack.

## Layout

```text
~/skill-set/
  default/
    workflow/SKILL.md
    security/SKILL.md

  dev/
    debugging/SKILL.md
    proof/SKILL.md
    code-review/SKILL.md

  product-management/
    specify/SKILL.md
    documentation/SKILL.md
    domain-modeling/SKILL.md
```

Each skill is a directory with a `SKILL.md` file. Skill directories may also be
symlinks to skill directories stored elsewhere.

Hidden directories, invalid set names, and `default` are excluded from
`skill-set list`. Set and skill directory names may contain letters, numbers,
dots, underscores, and hyphens. They may not contain slashes or start with a
dot.

By default, skills are linked into:

```text
~/.agents/skills
~/.claude/skills
~/.codex/skills
```

Override targets with a colon-separated `SKILL_TARGETS` value.

## Install

### Homebrew (preferred)

Tap this repository explicitly, then install the formula:

```sh
brew tap kreek/skill-set https://github.com/kreek/skill-set
brew install --HEAD skill-set
```

Homebrew installs `skill-set`, the `sklset` alias, and Bash and Zsh completion
files.

### From this repo

```sh
make install PREFIX=/usr/local
```

For a user-local install:

```sh
make install PREFIX="$HOME/.local"
```

Ensure `"$HOME/.local/bin"` is on `PATH`. `make install` also installs Bash and
Zsh completion files and creates the `sklset` alias symlink.

Bash completion is installed under
`$HOME/.local/share/bash-completion/completions`.

For Zsh, add the installed completion directory before running `compinit`:

```sh
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

### Direct script

Use this only when you do not want Homebrew or the repository installer:

```sh
install -m 0755 bin/skill-set /usr/local/bin/skill-set
ln -sf skill-set /usr/local/bin/sklset
```

## Usage

```sh
skill-set list
skill-set load dev ruby       # replace stack with dev then ruby
skill-set dev ruby            # shorthand for: skill-set load dev ruby
sklset dev                    # short alias for daily use
skill-set add python          # push python onto the stack
skill-set remove ruby         # remove ruby from the stack
skill-set current             # prints active stack, one set per line
skill-set unload              # clear active stack; default remains
skill-set sync                # link default without changing active stack
skill-set doctor              # show config and managed target counts
```

`skill-set load` accepts one or more set names. Loading the same stack is a
no-op. Passing no names to `skill-set load` is the same as `skill-set unload`.
`skill-set add` reports a no-op when the set is already active. `skill-set
remove` fails when the set is not active.

Source skill sets are read from `~/skill-set` by default, and state is stored in
`~/.skill-set`. Override paths for tests or unusual layouts:

```sh
SKILL_SETS=/path/to/skill-set TARGET_DIR=/tmp/home STATE_FILE=/tmp/state skill-set doctor
```

Use `SKILL_TARGETS` when target directories are not under one home-like root:

```sh
SKILL_TARGETS="$HOME/.agents/skills:$HOME/.claude/skills" skill-set dev
```

## Safety

- Mutating commands preflight target conflicts before changing the active stack.
- If a mutation fails after it starts, state and managed links are rolled back.
- Only symlinks that point to the previously active set are removed during
  swaps.
- Real directories and third-party symlinks are never overwritten.
- A skill name cannot appear in more than one of `default` or any set in the
  active stack. Conflicts abort the operation before any symlinks change.

## Troubleshooting

- `skill-set: no such skill set`: run `skill-set list` and load one of the listed directories.
- `skill-set: invalid skill set name`: rename the set directory to use only
  letters, numbers, dots, underscores, and hyphens.
- `skill-set: skill set listed more than once`: remove duplicate names from the
  `load` command.
- `target exists and is not a managed symlink`: remove or rename the conflicting target path before loading the set.
- `doctor` shows configured target directories and linked skill counts.

## Shell completion

Bash:

```sh
source completions/skill-set.bash
```

Zsh:

```sh
fpath=("$PWD/completions" $fpath)
autoload -Uz compinit && compinit
```

## Development

Install `shellcheck` and `shfmt`, and make sure `zsh` is available. Then run:

```sh
make check
```
