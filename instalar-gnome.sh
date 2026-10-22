#!/usr/bin/env bash
# ============================================================
#  Instalación automática de GNOME en Arch Linux
#  Correr como usuario normal (con sudo), NO como root.
#
#  Uso:
#    chmod +x instalar-gnome.sh && ./instalar-gnome.sh
#
#  Opciones (variables de entorno):
#    DM=gdm|lightdm   gestor de inicio de sesión (default: gdm)
#    EXTRA=1          instala también gnome-extra (apps adicionales, pesa más)
#    REBOOT=1         reinicia solo al terminar
#  Ejemplo:
#    DM=lightdm EXTRA=1 REBOOT=1 ./instalar-gnome.sh
# ============================================================
set -euo pipefail

DM="${DM:-gdm}"
EXTRA="${EXTRA:-0}"
REBOOT="${REBOOT:-0}"

[[ $EUID -eq 0 ]] && { echo "No corras esto como root, usa tu usuario normal."; exit 1; }
command -v sudo >/dev/null || { echo "Falta sudo."; exit 1; }
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || { echo "Sin internet."; exit 1; }

PAC="sudo pacman -S --needed --noconfirm"

echo "[*] Actualizando sistema..."
sudo pacman -Syu --noconfirm

echo "[*] Instalando GNOME..."
$PAC gnome gnome-tweaks
[[ "$EXTRA" == "1" ]] && $PAC gnome-extra

echo "[*] Red, audio, bluetooth, impresión..."
$PAC networkmanager pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
     bluez bluez-utils cups xdg-user-dirs xdg-utils

echo "[*] Fuentes y apps básicas..."
$PAC ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji firefox

echo "[*] Gestor de inicio de sesión: $DM"
case "$DM" in
    gdm)
        $PAC gdm
        sudo systemctl disable lightdm 2>/dev/null || true
        sudo systemctl enable gdm
        ;;
    lightdm)
        $PAC lightdm lightdm-gtk-greeter
        sudo systemctl disable gdm 2>/dev/null || true
        sudo systemctl enable lightdm
        ;;
    *)
        echo "DM inválido: usa gdm o lightdm"; exit 1 ;;
esac

echo "[*] Activando servicios..."
sudo systemctl enable NetworkManager bluetooth cups
# Si usabas systemd-networkd o dhcpcd, evita conflicto con NetworkManager
sudo systemctl disable dhcpcd 2>/dev/null || true

xdg-user-dirs-update

echo
echo "[+] Listo. GNOME instalado con $DM."
if [[ "$REBOOT" == "1" ]]; then
    echo "[*] Reiniciando en 5 segundos..."
    sleep 5
    sudo reboot
else
    echo "    Reinicia con: sudo reboot"
fi
