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

# ETCD stuff
export ETCDCTL_ENDPOINTS="https://127.0.0.1:2379"
export ETCDCTL_CACERT="/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt"
export ETCDCTL_CERT="/var/lib/rancher/k3s/server/tls/etcd/server-client.crt"
export ETCDCTL_KEY="/var/lib/rancher/k3s/server/tls/etcd/server-client.key"
export ETCDCTL_API=3


# Aliases
alias ls='ls --color=always'
alias grep='grep --color=always'
alias fgrep='fgrep --color=always'
alias egrep='egrep --color=always'
alias watch='watch --color --beep'

alias ll='ls -Falh'
alias kubectl='k3s kubectl'
alias k='k3s kubectl'
alias v='vim'
alias hh='history | grep'
alias rg='grep --color=always'
alias ipa='ip -br -c a'

# Completion
source /etc/profile.d/bash_completion.sh
command -v k3s &>/dev/null && . <(k3s completion bash)
