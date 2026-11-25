# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting web-search)

source $ZSH/oh-my-zsh.sh

bindkey '`' autosuggest-accept

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

############################################################################
############################################################################

outline() {
  INTERFACE="Wi-Fi"   # change to your device, f.e.: "Ethernet"
  KEYFILE="$HOME/.outline_key"

  # Helper to decode base64 URL-safe shadowsocks URI
  parse_ss() {
    local ss_uri="$1"
    # Remove prefix
    ss_uri="${ss_uri#ss://}"

    # If URI contains userinfo@host:port, extract userinfo first
    local userinfo_host_port="${ss_uri%%/*}"  # before first slash (or whole string)
    local params="${ss_uri#*/}"
    if [[ "$params" == "$userinfo_host_port" ]]; then
      params=""
    fi

    # userinfo is before @
    local userinfo="${userinfo_host_port%@*}"
    local host_port="${userinfo_host_port#*@}"

    # userinfo can be base64 encoded method:password or method:password in plain
    # If it looks like base64 (contains = or ends with something), decode it
    if [[ "$userinfo" =~ ^[A-Za-z0-9+/=]+$ ]]; then
      userinfo_decoded=$(echo "$userinfo" | base64 --decode 2>/dev/null)
      if [ $? -eq 0 ]; then
        userinfo="$userinfo_decoded"
      fi
    fi

    METHOD="${userinfo%%:*}"
    PASSWORD="${userinfo#*:}"

    SERVER_IP="${host_port%%:*}"
    SERVER_PORT="${host_port#*:}"

    # Optional query params parsing (e.g. ?outline=1) - ignoring for now

    # Export variables for use outside
    export METHOD PASSWORD SERVER_IP SERVER_PORT
  }

  # If called with an argument, treat it as a new ss:// URI
  if [ -n "$1" ]; then
    if [[ "$1" != ss://* ]]; then
      echo "Error: argument must start with ss://"
      return 1
    fi

    # Save the key to file (overwrite)
    echo "$1" > "$KEYFILE"
  else
    # No argument - load key from file
    if [ ! -f "$KEYFILE" ]; then
      echo "Error: no saved Outline key found. Please run:"
      echo "  outline ss://...."
      return 1
    fi
    set -- "$(cat "$KEYFILE")"  # reset $1 to saved key
  fi

  # Parse the ss:// key
  parse_ss "$1"

  # Now run the VPN (similar to before)
  networksetup -setsocksfirewallproxy "$INTERFACE" 127.0.0.1 1080
  networksetup -setsocksfirewallproxystate "$INTERFACE" on

  echo "Outline VPN enabled. Press Ctrl+C to disable."

  # Run ss-local in foreground
  ss-local -s "$SERVER_IP" -p "$SERVER_PORT" -l 1080 -k "$PASSWORD" -m "$METHOD"

  echo
  echo "Disabling Outline VPN..."

  networksetup -setsocksfirewallproxystate "$INTERFACE" off
}

export EDITOR="$HOME/.local/bin/neovide-patched"
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --zsh)"

alias inv='nvim $(fzf -m --preview="bat --color=always {}")'

# # Homebrew OpenJDK
# export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
#
# # Prefer this java first
# export PATH="$JAVA_HOME/bin:$PATH"
# # Java
export PATH="/Library/TeX/texbin:$PATH"

alias pi="cd ~/Home/itmo/pi"
alias pih="cd ~/Home/itmo/pi/hw/paradigms"

alias ad="cd ~/Home/itmo/ad"
alias adl="cd ~/Home/itmo/ad/lab"
alias adh="cd ~/Home/itmo/ad/hw"

alias dm="cd ~/Home/itmo/dm"
alias dml="cd ~/Home/itmo/dm/lab"
alias dmh="cd ~/Home/itmo/dm/hw"

alias ca="cd ~/Home/itmo/ca"
alias cal="cd ~/Home/itmo/ca/lab"

alias ma="cd ~/Home/itmo/ma"
alias mah="cd ~/Home/itmo/ma/hw"
alias mal="cd ~/Home/itmo/ma/lec"
alias mae="cd ~/Home/itmo/ma/exm"

alias cpp="cd ~/Home/itmo/cpp"
alias cpph="cd ~/Home/itmo/cpp/hw"

alias la="cd ~/Home/itmo/la"

alias lg="cd ~/Home/itmo/lg"
alias lgh="cd ~/Home/itmo/lg/hw"
alias lgn="cd ~/Home/itmo/lg/notes"

alias i="cd ~/Home/itmo"
alias h="cd ~/Home"

alias nv="nvim"
alias nd="$HOME/.local/bin/neovide-patched --fork"  # 0.16.2 + metal display-link vsync fix (key-repeat halving); patch: ~/.config/nvim/lua/diag/neovide-0.16.2-metal-displaylink-vsync.patch

alias cfg="cd ~/.config"
alias tmp="cd ~/Home/tmp"
alias dl="cd ~/Downloads"

alias stk="cd ~/Home/stark"

alias tp="cd ~/Home/teach/prog"

alias oc="opencode"

# Start an nREPL with cider middleware in the current directory.
# Writes .nrepl-port here; Conjure (in nvim) auto-connects to it.
alias cnrepl='clj -M:nrepl'

alias mcd=take

alias cls=clear
alias pcp="pwd | pbcopy"

cpf() {
  if (( $# == 0 )); then
    print -ru2 -- 'Usage: cpf FILE [FILE ...]'
    return 2
  fi

  local file_path
  local -a file_paths
  for file_path in "$@"; do
    if [[ ! -e $file_path && ! -L $file_path ]]; then
      print -ru2 -- "cpf: no such file: $file_path"
      return 1
    fi
    [[ $file_path = /* ]] || file_path=$PWD/$file_path
    file_paths+=("$file_path")
  done

  "$HOME/.local/bin/cpf-appkit" "${file_paths[@]}" || return $?
  print -rl -- "${file_paths[@]}"
}

# opencode
export PATH=/Users/vsndrg/.opencode/bin:$PATH


# ITMO homework: short symlinks for repos, e.g.
# nature-se-go-2026-c118-lrucache-a117-vsndrg -> lrucache
# nature-cs-2026-c126-isa_amd64-a99-vsndrg -> isa_amd64
_itmo_hw_dirs=(~/Home/itmo/go/hw ~/Home/itmo/os/hw)
_itmo_hw_links() {
  local hw d name
  for hw in $_itmo_hw_dirs; do
    [[ $PWD == $hw* ]] || continue
    for d in $hw/nature-*(N/); do
      [[ -L $d ]] && continue
      name=${${d:t}#nature-*-c<->-}
      name=${name%-a<->-*}
      [[ -e $hw/$name || -L $hw/$name ]] || ln -s ${d:t} $hw/$name
    done
  done
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _itmo_hw_links
export PATH="$HOME/.local/bin:$PATH"
