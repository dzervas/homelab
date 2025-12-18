{ pkgs, ... }:
{
  languages.jsonnet.enable = true;
  packages = with pkgs; [
    tanka
    jsonnet-bundler
    deploy-rs

    # pv-migrate
    yq-go
    pv-migrate
  ];

  scripts = {
    tk-diff-all.exec = "tk env list --names | xargs -n1 --verbose tk diff -s";
    tk-chart-add.exec = ''test "$#" -eq 4 || echo "Usage: tk-chart-add <repo-url> <repo-name> <chart-name> <chart-version>" && tk tool charts add-repo $3 $1 && tk tool charts add $3/$2@$4'';
    tk-update-check.exec = ''
    	echo "This is going to take some time..."
     	echo
      tk tool charts version-check | \
      	jq -r 'map(
       		.name + " " + .current_version + (
         		if .current_version ==  .latest_version.version then
		          " ✅"
						else
							" -> " + .latest_version.version + " 🔃"
						end
					)) | .[]'
    '';
  };

  env = {
    TANKA_PAGER = "${pkgs.bat}/bin/bat -p -l yaml";
  };
}
