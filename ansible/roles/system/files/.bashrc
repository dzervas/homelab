# Managed by Ansible
[ -z "$PS1" ] && return

# Bash settings
shopt -s histappend

HISTCONTROL=ignoredups:ignorespace
HISTSIZE=10000
HISTFILESIZE=20000

# Title
# update_title() {
# 	echo -ne "\033]0;$USER@$(hostname -s): $BASH_COMMAND\007"
# }
# trap update_title DEBUG
# PROMPT_COMMAND="echo -ne \"\033]0;$(hostname -s): $BASH_COMMAND\007\""

# Prompt
hash=$(echo $(hostname -s) | cksum | cut -d ' ' -f1)
color=$(( 31 + (hash % 6) )) # Using modulo to select from range (31 to 36)

export PS1="\u@\[\e[1;${color}m\]\h\[\e[m\]:\w\$ "

# Aliases
alias ls='ls --color=always'
alias grep='grep --color=always'
alias fgrep='fgrep --color=always'
alias egrep='egrep --color=always'
alias watch='watch --color --beep'

alias ll='ls -Fal'
alias k='kubectl'
alias v='vim'
alias hh='history | grep'
alias rg='grep --color=always'
alias ipa='ip -br -c a'
