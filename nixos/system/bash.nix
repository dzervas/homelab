{ pkgs, ... }: {
  programs.bash = {
    promptInit = ''
      hosthash=$(echo $(hostname -s) | cksum | cut -d ' ' -f1)
      hostcolor=$(( 31 + (hosthash % 6) )) # Using modulo to select from range (31 to 36)

      export PS1="\u@\[\e[1;''${hostcolor}m\]\h\[\e[m\]:\w\$ "
    '';
    shellAliases = {
      ls = "ls --color=always";
      grep = "grep --color=always";
      fgrep = "fgrep --color=always";
      egrep = "egrep --color=always";
      watch = "watch --color --beep";
      kubectl = "k3s kubectl";

      ll = "ls -Falh";
      k = "k3s kubectl";
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
    '';
  };

  environment.systemPackages = with pkgs; [
    vim
  ];
}
