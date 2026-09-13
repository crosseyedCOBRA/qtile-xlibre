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
  # X11 / LightDM / dwm
  # ------------------------------------------------------------

  services.xserver = {
    enable = true;

    xkb.layout = "us";

    displayManager.lightdm = {
      enable = true;
      greeters.gtk.enable = true;
    };

    windowManager.dwm = {
      enable = true;

      package = pkgs.dwm.overrideAttrs (oldAttrs: {
        postPatch = (oldAttrs.postPatch or "") + ''
          cp ${./dwm-config.h} config.h
        '';
      });
    };
  };

  # ------------------------------------------------------------
  # Graphics
  # ------------------------------------------------------------

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

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

    # Audio
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

    # X11 utilities
    xorg.xev
    xorg.xkill
    xorg.xrandr
    xorg.xdpyinfo
    xorg.xprop
  ];

  # ------------------------------------------------------------
  # Services
  # ------------------------------------------------------------

  services.libinput.enable = true;

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
