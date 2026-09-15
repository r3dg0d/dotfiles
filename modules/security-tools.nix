{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Network discovery, capture and diagnostics
    nmap
    masscan
    rustscan
    tcpdump
    aircrack-ng
    bettercap
    netcat-openbsd
    socat
    dnsutils
    whois
    traceroute
    arp-scan
    # Web, credentials and authorized exploitation
    hashcat
    john
    sqlmap
    nikto
    gobuster
    ffuf
    dirb
    thc-hydra
    metasploit
    mitmproxy
    enum4linux
    samba
    python3Packages.impacket
    # Forensics and reverse engineering
    binwalk
    exiftool
    foremost
    radare2
    yara
    sleuthkit
    volatility3
    # Crypto and proxy clients (no network daemons enabled)
    testssl
    openssl
    gnupg
    age
    tor
    proxychains-ng
  ];
  # Includes tshark; avoid installing a second Wireshark variant.
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };
  users.users.${config.workstation.username}.extraGroups = [ "wireshark" ];
}
