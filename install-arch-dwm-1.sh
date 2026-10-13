#!/usr/bin/env bash
# Instalador de Arch Linux minimalista (dwm, sin DE, kernel lts, nano, fastfetch)
# Correr desde el live ISO de Arch, como root:  bash install-arch-dwm.sh
# Solo usa repos oficiales (nada del AUR).
set -euo pipefail

# ---------- Config (edita a tu gusto) ----------
HOSTNAME="Archlinux"
USERNAME="void"
TIMEZONE="America/Monterrey"
LOCALE="es_MX.UTF-8"
KEYMAP="la-latin1"
# -----------------------------------------------

[[ $EUID -eq 0 ]] || { echo "Corre esto como root."; exit 1; }

# Limpia restos de un intento anterior (si /mnt quedó montado)
umount -R /mnt 2>/dev/null || true

echo ">> Checando internet..."
ping -c1 -W3 archlinux.org >/dev/null || { echo "Sin internet. Conéctate (iwctl para WiFi) y reintenta."; exit 1; }

if [[ -d /sys/firmware/efi/efivars ]]; then BOOTMODE=uefi; else BOOTMODE=bios; fi
echo ">> Modo de arranque: $BOOTMODE"

lsblk -dpno NAME,SIZE,MODEL | grep -v loop
echo
read -rp "Disco donde instalar (ej. /dev/sda): " DISK
[[ -b $DISK ]] || { echo "$DISK no existe."; exit 1; }
echo "!!! SE BORRARÁ TODO en $DISK !!!"
read -rp "Escribe el nombre del disco otra vez para confirmar: " CONFIRM
[[ $CONFIRM == "$DISK" ]] || { echo "No coincide. Cancelado."; exit 1; }

read -rsp "Contraseña de root: " ROOT_PASS; echo
read -rsp "Contraseña de $USERNAME: " USER_PASS; echo

if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then P="${DISK}p"; else P="$DISK"; fi

timedatectl set-ntp true

echo ">> Particionando..."
wipefs -af "$DISK"
if [[ $BOOTMODE == uefi ]]; then
  parted -s "$DISK" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB set 1 esp on \
    mkpart root ext4 513MiB 100%
  mkfs.fat -F32 "${P}1"
  mkfs.ext4 -F "${P}2"
  mount "${P}2" /mnt
  mkdir -p /mnt/boot
  mount "${P}1" /mnt/boot
else
  parted -s "$DISK" mklabel msdos \
    mkpart primary ext4 1MiB 100% set 1 boot on
  mkfs.ext4 -F "${P}1"
  mount "${P}1" /mnt
fi

echo ">> Instalando paquetes base..."
PKGS=(base linux-lts linux-firmware intel-ucode base-devel nano sudo
      networkmanager grub mesa
      xorg-server xorg-xinit xorg-xsetroot
      dmenu feh fastfetch git ttf-dejavu zram-generator
      libx11 libxft libxinerama freetype2 fontconfig)
[[ $BOOTMODE == uefi ]] && PKGS+=(efibootmgr)
pacstrap -K /mnt "${PKGS[@]}"

genfstab -U /mnt >> /mnt/etc/fstab

echo ">> Configurando el sistema..."
arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
sed -i "s/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo 'export EDITOR=nano' > /etc/profile.d/editor.sh

# zram como swap (útil con poca RAM)
cat > /etc/systemd/zram-generator.conf <<ZRAM
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

useradd -m -G wheel -s /bin/bash $USERNAME
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager

# dwm y st ya no están en los repos de Arch: se compilan del código oficial de suckless
for app in dwm st; do
  git clone https://git.suckless.org/\$app /tmp/\$app
  make -C /tmp/\$app clean install
done
rm -rf /tmp/dwm /tmp/st

if [ "$BOOTMODE" = uefi ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
  # copia de respaldo por si el firmware es mañoso
  grub-install --target=x86_64-efi --efi-directory=/boot --removable
else
  grub-install --target=i386-pc $DISK
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Contraseñas (fuera del heredoc para que los caracteres raros no se rompan)
echo "root:$ROOT_PASS" | arch-chroot /mnt chpasswd
echo "$USERNAME:$USER_PASS" | arch-chroot /mnt chpasswd

echo ">> Dotfiles de $USERNAME..."
H="/mnt/home/$USERNAME"

cat > "$H/.bash_profile" <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
# Arranca dwm automáticamente en tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
  exec startx
fi
EOF

cat > "$H/.bashrc" <<'EOF'
[[ $- != *i* ]] && return
PS1='\u@\h:\w\$ '
alias ls='ls --color=auto'
alias ll='ls -lah'
alias update='sudo pacman -Syu'
export EDITOR=nano
command -v fastfetch >/dev/null && fastfetch
EOF

cat > "$H/.xinitrc" <<'EOF'
#!/bin/sh
# Fondo: si pones un wallpaper en ~/wallpaper.jpg se usa; si no, color sólido
if [ -f "$HOME/wallpaper.jpg" ]; then
  feh --bg-fill "$HOME/wallpaper.jpg" &
else
  xsetroot -solid '#14233c'
fi

# Barra de estado de dwm
(
while true; do
  load=$(cut -d' ' -f1 /proc/loadavg)
  mem=$(free -m | awk '/Mem:/ {printf "%d%%", $3*100/$2}')
  bat=""
  [ -r /sys/class/power_supply/BAT0/capacity ] && bat=" | BAT $(cat /sys/class/power_supply/BAT0/capacity)%"
  xsetroot -name " LOAD $load | RAM $mem$bat | $(date '+%d/%m/%y %a %H:%M') "
  sleep 5
done
) &

exec dwm
EOF

chmod +x "$H/.xinitrc"
arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

umount -R /mnt

cat <<MSG

==================================================
Listo. Quita el USB y reinicia con:  reboot
Inicia sesión como $USERNAME en tty1 y arranca dwm solo.

Atajos de dwm (Mod = Alt):
  Alt + Shift + Enter   terminal (st)
  Alt + p               lanzador (dmenu)
  Alt + 1..9            cambiar de tag
  Alt + Shift + q       salir de dwm

WiFi:  nmtui
==================================================
MSG
