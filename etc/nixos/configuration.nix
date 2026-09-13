{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ------------------------------------------------------------
  # Boot
  # ------------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ------------------------------------------------------------
  # Networking
  # ------------------------------------------------------------

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------
  # X11
  # ------------------------------------------------------------

  services.xserver = {
    enable = true;

    xkb.layout = "us";

    displayManager.lightdm = {
      enable = true;
      greeters.gtk.enable = true;
    };

    windowManager.dwm.enable = true;
  };

  # ------------------------------------------------------------
  # Graphics
  # ------------------------------------------------------------

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # ------------------------------------------------------------
  # Audio
  # ------------------------------------------------------------

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  security.rtkit.enable = true;

  # ------------------------------------------------------------
  # User
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # Flatpak + XDG Desktop Portal
  # ------------------------------------------------------------

  services.flatpak.enable = true;

  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];

    config.common.default = [
      "gtk"
    ];
  };

  # ------------------------------------------------------------
  # Desktop / Applications
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    # Terminal
    alacritty

    # Application launcher
    rofi

    # Notifications
    dunst
    libnotify

    # XDG integration
    xdg-utils

    # Audio control
    pavucontrol

    # Development
    git

    # Basic utilities
    vim
    wget
    curl
    unzip
    zip

    # System information
    htop
    tree
    pciutils
    usbutils

    # X11 troubleshooting / utilities
    xorg.xev
    xorg.xkill
    xorg.xrandr
    xorg.xdpyinfo
    xorg.xprop
  ];

  # ------------------------------------------------------------
  # Nix
  # ------------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
  ];

  # ------------------------------------------------------------
  # System State Version
  # ------------------------------------------------------------

  system.stateVersion = "26.05";
}
