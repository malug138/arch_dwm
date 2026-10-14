#!/usr/bin/env bash
# ============================================================
#  Post-instalación Arch Linux: sistema "normal" + tools tipo Kali
#  Correr como usuario normal (con sudo), NO como root.
#  Uso:  chmod +x post-install.sh && ./post-install.sh
# ============================================================
set -uo pipefail

R='\e[31m'; G='\e[32m'; Y='\e[33m'; B='\e[34m'; N='\e[0m'
msg()  { echo -e "${B}[*]${N} $*"; }
ok()   { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
err()  { echo -e "${R}[-]${N} $*"; }

FALLIDOS=()

[[ $EUID -eq 0 ]] && { err "No corras esto como root, usa tu usuario normal."; exit 1; }
command -v sudo >/dev/null || { err "Falta sudo (pacman -S sudo como root)."; exit 1; }
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || { err "Sin internet."; exit 1; }

sudo -v
# Mantener sudo vivo mientras corre el script
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &

# Instala paquete por paquete; si uno no existe, lo salta y lo anota
instalar() {
    local p
    for p in "$@"; do
        if pacman -Si "$p" >/dev/null 2>&1 || pacman -Qi "$p" >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 \
                && echo "    ok  $p" || { echo "    FALLÓ $p"; FALLIDOS+=("$p"); }
        else
            echo "    no existe en repos: $p"; FALLIDOS+=("$p")
        fi
    done
}

# ------------------------------------------------------------
# 1. Sistema base + drivers
# ------------------------------------------------------------
paso_base() {
    msg "Actualizando sistema..."
    sudo pacman -Syu --noconfirm

    msg "Utilidades base..."
    instalar base-devel git curl wget unzip zip p7zip unrar man-db man-pages \
        bash-completion ntfs-3g exfatprogs dosfstools mtools rsync openssh \
        htop btop fastfetch tree lsof usbutils pciutils xdg-user-dirs xdg-utils \
        reflector linux-firmware linux-lts-headers nano vim jq bc

    # Microcódigo
    if grep -qi intel /proc/cpuinfo; then instalar intel-ucode; fi
    if grep -qi amd   /proc/cpuinfo; then instalar amd-ucode;   fi

    # Driver de video (según tu GPU). Usa variantes -lts si tienes kernel lts.
    msg "Detectando GPU..."
    local gpu; gpu=$(lspci | grep -Ei 'vga|3d' || true)
    echo "    $gpu"
    instalar mesa vulkan-icd-loader
    if   echo "$gpu" | grep -qi nvidia; then
        if pacman -Q linux-lts >/dev/null 2>&1; then instalar nvidia-lts nvidia-utils nvidia-settings
        else instalar nvidia nvidia-utils nvidia-settings; fi
    elif echo "$gpu" | grep -qi amd;    then instalar vulkan-radeon xf86-video-amdgpu
    elif echo "$gpu" | grep -qi intel;  then instalar vulkan-intel intel-media-driver
    fi

    msg "Red, bluetooth, impresión, audio..."
    instalar networkmanager network-manager-applet bluez bluez-utils blueman cups \
        pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber pavucontrol alsa-utils

    msg "Fuentes..."
    instalar ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji noto-fonts-cjk \
        ttf-jetbrains-mono-nerd ttf-font-awesome

    msg "Activando servicios..."
    sudo systemctl enable --now NetworkManager bluetooth cups fstrim.timer systemd-timesyncd 2>/dev/null
    xdg-user-dirs-update
    ok "Base lista."
}

# ------------------------------------------------------------
# 2. Xorg + apps de uso diario
# ------------------------------------------------------------
paso_apps() {
    msg "Xorg y utilidades..."
    instalar xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xrdb xclip xdotool \
        picom feh dunst rofi flameshot brightnessctl playerctl

    msg "Apps de escritorio..."
    instalar firefox alacritty thunar thunar-archive-plugin thunar-volman file-roller gvfs \
        gvfs-mtp tumbler vlc mpv evince libreoffice-fresh gimp obs-studio \
        qbittorrent keepassxc gparted
    ok "Apps listas."
}

# ------------------------------------------------------------
# 3. Entorno de escritorio (opcional)
# ------------------------------------------------------------
paso_de() {
    echo "  1) Ninguno (sigues con tu WM)"
    echo "  2) XFCE"
    echo "  3) GNOME"
    echo "  4) KDE Plasma"
    read -rp "Elige DE [1-4]: " de
    case "$de" in
        2) instalar xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
           sudo systemctl enable lightdm ;;
        3) instalar gnome gnome-tweaks gdm
           sudo systemctl enable gdm ;;
        4) instalar plasma-meta kde-applications-meta sddm
           sudo systemctl enable sddm ;;
        *) msg "Sin DE." ;;
    esac
}

# ------------------------------------------------------------
# 4. yay (AUR helper)
# ------------------------------------------------------------
paso_yay() {
    if command -v yay >/dev/null; then ok "yay ya está instalado."; return; fi
    msg "Instalando yay..."
    local d; d=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$d/yay-bin" \
        && (cd "$d/yay-bin" && makepkg -si --noconfirm) \
        && ok "yay instalado." || { err "Falló yay"; FALLIDOS+=("yay"); }
    rm -rf "$d"
}

# ------------------------------------------------------------
# 5. Herramientas tipo Kali desde repos oficiales de Arch
# ------------------------------------------------------------
paso_kali_oficial() {
    msg "Herramientas de pentesting (repos oficiales)..."
    instalar \
        nmap masscan wireshark-qt wireshark-cli tcpdump ettercap bettercap \
        aircrack-ng hashcat john hydra sqlmap nikto gobuster ffuf \
        macchanger openbsd-netcat socat proxychains-ng tor torsocks \
        binwalk radare2 ghidra gdb nasm foremost testdisk \
        bind whois traceroute hping smbclient nbtscan \
        python-impacket impacket \
        wireguard-tools openvpn
    # Wireshark sin root
    sudo usermod -aG wireshark "$USER" 2>/dev/null
    ok "Listo (relogueate para que aplique el grupo wireshark)."
}

# ------------------------------------------------------------
# 6. Repo BlackArch (el equivalente más cercano a Kali en Arch)
# ------------------------------------------------------------
paso_blackarch() {
    if ! grep -q '^\[blackarch\]' /etc/pacman.conf; then
        msg "Descargando strap.sh de BlackArch..."
        local d; d=$(mktemp -d); cd "$d" || return
        curl -fsSLO https://blackarch.org/strap.sh || { err "No pude bajar strap.sh"; return; }
        echo
        warn "Compara este SHA1 con el de https://blackarch.org/downloads.html"
        sha1sum strap.sh
        read -rp "¿Coincide? Continuar [s/N]: " c
        [[ "$c" =~ ^[sS]$ ]] || { warn "Cancelado."; return; }
        chmod +x strap.sh && sudo ./strap.sh || { err "Falló strap.sh"; return; }
        cd ~ || true
    else
        ok "BlackArch ya está configurado."
    fi
    sudo pacman -Syu --noconfirm

    echo
    echo "  1) Selección tipo 'kali-tools-top10' + extras comunes (recomendado, ligero)"
    echo "  2) Por categorías (blackarch-webapp, -recon, -wireless, etc.)"
    echo "  3) TODO el repo 'blackarch' (+3000 tools, ~100GB, no recomendado)"
    read -rp "Elige [1-3]: " op
    case "$op" in
        1) instalar metasploit burpsuite netexec responder bettercap enum4linux-ng \
              wpscan dirb dirbuster theharvester recon-ng sherlock spiderfoot \
              evil-winrm bloodhound crunch cewl wordlistctl seclists \
              rockyou 2>/dev/null
           ;;
        2) sudo pacman -Sg | grep -i '^blackarch' | sort -u
           read -rp "Categorías separadas por espacio (ej: blackarch-webapp blackarch-recon): " cats
           # shellcheck disable=SC2086
           [[ -n "$cats" ]] && sudo pacman -S --needed $cats
           ;;
        3) sudo pacman -S --needed blackarch ;;
        *) msg "Saltando tools de BlackArch." ;;
    esac
}

# ------------------------------------------------------------
# Menú
# ------------------------------------------------------------
menu() {
    echo
    echo "=============================================="
    echo "  Post-instalación Arch (normal + tipo Kali)"
    echo "=============================================="
    echo "  1) Todo (base + apps + yay + kali oficial + blackarch)"
    echo "  2) Solo base (drivers, red, audio, fuentes)"
    echo "  3) Solo Xorg + apps de escritorio"
    echo "  4) Instalar un DE (XFCE/GNOME/KDE)"
    echo "  5) yay (AUR)"
    echo "  6) Solo tools de pentesting (oficial)"
    echo "  7) Solo BlackArch"
    echo "  0) Salir"
    read -rp "Opción: " o
    case "$o" in
        1) paso_base; paso_apps; paso_de; paso_yay; paso_kali_oficial; paso_blackarch ;;
        2) paso_base ;;
        3) paso_apps ;;
        4) paso_de ;;
        5) paso_yay ;;
        6) paso_kali_oficial ;;
        7) paso_blackarch ;;
        0) exit 0 ;;
        *) err "Opción inválida"; menu ;;
    esac
}

menu

echo
if ((${#FALLIDOS[@]})); then
    warn "Paquetes que no se instalaron (no existen o fallaron):"
    printf '    - %s\n' "${FALLIDOS[@]}"
    warn "Búscalos con: pacman -Ss <nombre>  o  yay -Ss <nombre>"
fi
ok "Terminado. Reinicia para aplicar todo."
