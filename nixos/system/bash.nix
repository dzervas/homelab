{ lib, pkgs, ... }: {
  environment.systemPackages = map lib.lowPrio (with pkgs; [
    btop
    curl
    dig
    dnslookup
    git
    jq
  ]);

  programs = {
    bash = {
      # Bash hackery to generate different hostname colors per node by hashing the hostname
      promptInit = ''
        hosthash=$(echo $(hostname -s) | cksum | cut -d ' ' -f1)
        hostcolor=$(( 31 + (hosthash % 7) )) # Using modulo to select from range (31 to 37)

        # double tick is the way that nix escapes the dolar-braces notation
        export PS1="\[\e[1;36m\]󱄅 \[\e[1;''${hostfrontcolor}m\]\h\[\e[m\]:\w\\$ "
      '';
      shellInit = ''
        shopt -s histappend

        HISTCONTROL=ignoredups:ignorespace
        HISTSIZE=10000
        HISTFILESIZE=20000

        export TERM="xterm-256color"
      '';

      shellAliases = {
        ls = "ls --color=always";
        grep = "grep --color=always";
        fgrep = "fgrep --color=always";
        egrep = "egrep --color=always";
        watch = "watch --color --beep";
        htop = "btop";

        ll = "ls -Falh";
        k = "kubectl";
        v = "vim";
        hh = "history | grep";
        rg = "grep --color=always";
        ipa = "ip -br -c a";
      };
    };
    vim = {
      enable = true;
      defaultEditor = true;
    };
  };
}
