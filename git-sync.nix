{config, ...}: {
  services.git-sync = {
    enable = true;
    repositories = {
      manager = {
        path = "${config.home.homeDirectory}/.config/home-manager";
        uri = "git@github.com:ecyshor/home-manager.git";
      };
    };
  };
}
