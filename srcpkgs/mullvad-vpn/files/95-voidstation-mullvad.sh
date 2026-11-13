# Mullvad VPN: firewall during boot (replaces mullvad-early-boot-blocking.service)
if [ -x /usr/bin/mullvad-daemon ]; then
  MULLVAD_RESOURCE_DIR="/opt/Mullvad VPN/resources/" timeout 10 /usr/bin/mullvad-daemon -v --initialize-early-boot-firewall >/dev/null 2>&1 || true
fi
