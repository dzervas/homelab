_: {
  programs = {
    bash = {
      promptInit = ''
      hosthash=$(echo $(hostname -s) | cksum | cut -d ' ' -f1)
      hostcolor=$(( 31 + (hosthash % 6) )) # Using modulo to select from range (31 to 36)

      export TERM="xterm-256color"
      export PS1="\[\e[1;36m\]󱄅 \[\e[1;''${hostcolor}m\]\h\[\e[m\]:\w\\$ "
      '';
      shellAliases = {
        ls = "ls --color=always";
        grep = "grep --color=always";
        fgrep = "fgrep --color=always";
        egrep = "egrep --color=always";
        watch = "watch --color --beep";

        ll = "ls -Falh";
        k = "kubectl";
        v = "vim";
        hh = "history | grep";
        rg = "grep --color=always";
        ipa = "ip -br -c a";
      };
      shellInit = ''
      shopt -s histappend

      HISTCONTROL=ignoredups:ignorespace
      HISTSIZE=10000
      HISTFILESIZE=20000

      export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"
      export PATH="$PATH:/var/lib/rancher/rke2/bin"
      '';
    };
    vim = {
      enable = true;
      defaultEditor = true;
    };
  };
}
