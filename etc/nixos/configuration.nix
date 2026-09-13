{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  services.xserver = {
    enable = true;
    xkb.layout = "us";

    displayManager.lightdm = {
      enable = true;
      greeters.gtk.enable = true;
    };

    windowManager.dwm.enable = true;
  };

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };

  security.rtkit.enable = true;

  users.users.mike = {
    isNormalUser = true;
    description = "Mike";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
  };

  environment.systemPackages = with pkgs; [
    alacritty
    rofi
    git
    vim
    wget
    curl
    xorg.xrandr
    xorg.xev
  ];

  services.libinput.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
  ];

  system.stateVersion = "26.05";
}
