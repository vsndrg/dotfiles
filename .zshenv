. "$HOME/.cargo/env"

# Go
export GOPATH="$HOME/go"
path=(/usr/local/go/bin $GOPATH/bin $path)
typeset -U path PATH
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
