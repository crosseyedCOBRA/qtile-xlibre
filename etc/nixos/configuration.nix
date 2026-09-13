{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ---------------------------------------------------------
  # Boot
  # ---------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.systemd-boot.configurationLimit = 10;

  # ---------------------------------------------------------
  # Networking
  # ---------------------------------------------------------

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # ---------------------------------------------------------
  # Locale / Time
  # ---------------------------------------------------------

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------------------------------------------------------
  # X11 + LightDM + bspwm
  # ---------------------------------------------------------

  services.xserver = {
    enable = true;

    displayManager.lightdm = {
      enable = true;

      greeters.gtk.enable = true;
    };

    windowManager.bspwm.enable = true;
  };

  services.displayManager.defaultSession = "bspwm";

  # ---------------------------------------------------------
  # Audio - PipeWire
  # ---------------------------------------------------------

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
  };

  # ---------------------------------------------------------
  # Graphics
  # ---------------------------------------------------------

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ---------------------------------------------------------
  # Flatpak
  # ---------------------------------------------------------

  services.flatpak.enable = true;

  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # ---------------------------------------------------------
  # Steam
  # ---------------------------------------------------------

  nixpkgs.config.allowUnfree = true;

  programs.steam = {
    enable = true;
  };

  # ---------------------------------------------------------
  # Bluetooth
  # ---------------------------------------------------------

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ---------------------------------------------------------
  # User
  # ---------------------------------------------------------

  users.users.mike = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # ---------------------------------------------------------
  # Basic Software
  # ---------------------------------------------------------

  environment.systemPackages = with pkgs; [
    # System / terminal
    git
    wget
    curl
    unzip
    zip
    p7zip

    # Editors
    vim
    nano

    # System monitoring
    btop
    fastfetch

    # X11 utilities
    xorg.xrandr
    xorg.xev
    xorg.xprop
    xorg.xdpyinfo
    xclip

    # Desktop utilities
    rofi
    dunst
    picom
    feh
    thunar
    pavucontrol
    flameshot

    # Bluetooth
    bluez
    blueman

    # Development basics
    gcc
    gnumake
    cmake
    pkg-config
  ];

  # ---------------------------------------------------------
  # Fonts
  # ---------------------------------------------------------

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    noto-fonts
    noto-fonts-emoji
  ];

  # ---------------------------------------------------------
  # Environment
  # ---------------------------------------------------------

  environment.variables = {
    EDITOR = "nano";
  };

  # ---------------------------------------------------------
  # Nix
  # ---------------------------------------------------------

  nix.settings = {
    experimental-features = [
      "nix-command"
    ];

    auto-optimise-store = true;
  };

  # ---------------------------------------------------------
  # System Version
  # ---------------------------------------------------------

  system.stateVersion = "26.05";
}{ config, pkgs, ... }:

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
  # Locale / Time
  # ------------------------------------------------------------

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  # ------------------------------------------------------------
  # X11
  # ------------------------------------------------------------

  services.xserver = {
    enable = true;

    # LightDM
    displayManager.lightdm = {
      enable = true;
      greeters.gtk.enable = true;
    };

    # Qtile
    windowManager.qtile = {
      enable = true;

      extraPackages = python3Packages: with python3Packages; [
        qtile-extras
      ];
    };
  };

  # Explicitly use the X11 Qtile session
  services.displayManager.defaultSession = "qtile";

  # ------------------------------------------------------------
  # Audio
  # ------------------------------------------------------------

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
  };

  # ------------------------------------------------------------
  # Flatpak
  # ------------------------------------------------------------

  services.flatpak.enable = true;

  # ------------------------------------------------------------
  # Steam
  # ------------------------------------------------------------

  programs.steam = {
    enable = true;
  };

  # ------------------------------------------------------------
  # Graphics
  # ------------------------------------------------------------

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ------------------------------------------------------------
  # User
  # ------------------------------------------------------------

  users.users.mike = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
  };

  # Allow sudo for mike
  security.sudo.wheelNeedsPassword = true;

  # ------------------------------------------------------------
  # Packages
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [

    # Basic utilities
    git
    wget
    curl
    unzip
    zip

    # Terminal/editor
    vim
    nano

    # System information / monitoring
    btop
    fastfetch

    # X11 utilities
    xorg.xrandr
    xorg.xev
    xorg.xprop
    xorg.xdpyinfo
    xclip

    # Qtile helpers
    rofi
    dunst
    picom
    feh

    # File management
    thunar

    # Audio
    pavucontrol

    # Bluetooth
    bluez
    blueman

    # Screenshot
    flameshot

    # Archive utilities
    p7zip

    # Build/development tools
    gcc
    gnumake
    cmake
    pkg-config

    # ZarisWM development dependencies
    glib
    libxcb
    xcb-util
    xcb-util-cursor
    xcb-util-keysyms
    xcb-util-wm
    xcb-util-image
    xcb-util-renderutil
  ];

  # ------------------------------------------------------------
  # Bluetooth
  # ------------------------------------------------------------

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ------------------------------------------------------------
  # Fonts
  # ------------------------------------------------------------

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    noto-fonts
    noto-fonts-emoji
  ];

  # ------------------------------------------------------------
  # Environment
  # ------------------------------------------------------------

  environment.variables = {
    EDITOR = "nano";
  };

  # ------------------------------------------------------------
  # Nix settings
  # ------------------------------------------------------------

  nix.settings = {
    experimental-features = [
      "nix-command"
    ];

    auto-optimise-store = true;
  };

  # Keep old generations around so we can roll back if needed.
  boot.loader.systemd-boot.configurationLimit = 10;

  # ------------------------------------------------------------
  # State version
  # ------------------------------------------------------------

  system.stateVersion = "26.05";
}
