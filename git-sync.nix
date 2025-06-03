{config, ...}: {
  services.git-sync = {
    enable = false;
    repositories = {
      manager = {
        path = "${config.home.homeDirectory}/.config/home-manager";
        uri = "git@github.com:ecyshor/home-manager.git";
        interval = 43200;
      };
    };
  };
}
