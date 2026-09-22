# Firefox configured so that .loki (and .snode) names resolve through the
# system resolver (systemd-resolved -> lokinet0 -> 127.3.2.1) instead of
# Firefox's built-in DNS-over-HTTPS, which would send those queries to a
# public DoH resolver that cannot answer them. Mullvad already provides
# private DNS for clearnet via its own resolver, so Firefox DoH is redundant
# here and only breaks overlay names.
{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;

    policies = {
      # Turn Firefox's own DoH off and lock it, so it always uses the OS
      # resolver. This is what makes .loki reachable while Mullvad is up.
      DNSOverHTTPS = {
        Enabled = false;
        Locked = true;
      };
    };

    # Locked prefs (belt-and-suspenders around the policy above).
    preferences = {
      # trr.mode 5 = DoH explicitly disabled.
      "network.trr.mode" = 5;
      # If DoH is ever re-enabled in fallback mode, still never send overlay
      # names to it.
      "network.trr.excluded-domains" = "loki,snode";
      # Don't turn a bare "foo.loki" typed in the bar into a search query.
      "browser.fixup.domainsuffixwhitelist.loki" = true;
    };
  };
}
