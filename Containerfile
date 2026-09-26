FROM ghcr.io/ohaiibuzzle/cachy-bootc:latest AS base

FROM base AS aur-builder

RUN pacman -Syu --noconfirm base-devel sudo git && \
    useradd builder && \
    echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir /built_pkgs/

WORKDIR /tmp

# RUN sudo -u builder git clone https://aur.archlinux.org/libfprint-cs9711-rebase-git.git package && \
#    cd package && \
#    sudo -u builder makepkg -s --noconfirm && \
#    cp *.tar.zst /built_pkgs/ && \
#    cd ../ && rm -rf package

RUN sudo -u builder git clone https://aur.archlinux.org/visual-studio-code-bin.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

FROM base AS system-image

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    7zip ark amd-ucode base base-devel bash-completion btop btrfs-progs \
    cpio dbus dbus-glib discover distrobox dmemcg-booster dolphin dosfstools dracut \
    e2fsprogs efibootmgr fcitx5-anthy fcitx5-im fcitx5-unikey firefox flatpak \
    flatpak-kcm gamescope-session-cachyos git glib2 gptfdisk \
    ibus intel-ucode jq just kate kwalletmanager linux-cachyos \
    linux-cachyos-nvidia-open linux-firmware mangohud man-db mpv nano \
    networkmanager noto-fonts noto-fonts-cjk noto-fonts-extra \
    nvtop opencl-mesa opencl-nvidia openssh ostree parallel\
    partitionmanager pipewire pipewire-jack plasma plasma-foreground-booster plasma-login-manager \
    plasma-systemmonitor plymouth plymouth-kcm podman \
    power-profiles-daemon sbctl shadow skopeo starship \
    steam-devices systemd tailscale vulkan-radeon wireplumber \
    xbindkeys xfsprogs yakuake zram-generator

# Copy packages from AUR Builder
COPY --from=aur-builder /built_pkgs/ /tmp/built_pkgs/

# Install AUR packages
RUN ls /tmp/built_pkgs && \
    pacman -U --noconfirm /tmp/built_pkgs/*.tar.zst && \
    rm -rf /tmp/built_pkgs

# Install fprintd after the AUR packages (in case a custom libfprint is built above)
RUN pacman -S --noconfirm fprintd

# Cleanup
COPY build_files/ /

RUN pacman -Scc --noconfirm && \
    echo -e "en_US.UTF-8 UTF-8\nen_GB.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && \
    echo -e '\neval $(starship init bash)' >> /etc/bash.bashrc && \
    plymouth-set-default-theme bgrt && \
    systemctl enable NetworkManager power-profiles-daemon bluetooth plasmalogin && \
    mkdir -p /usr/lib/bootc/kargs.d/ && \
    echo 'kargs = ["quiet", "splash", "zswap.enabled=0"]' > /usr/lib/bootc/kargs.d/00-splash.toml && \
    echo 'Error "UCM support temporary disabled for ${CardLongName}"' >> /usr/share/alsa/ucm2/USB-Audio/Sony/DualSense-PS5.conf


# https://github.com/bootc-dev/bootc/issues/1801
# /var/lib/pacman is kept for chunkah to read and pruned from the final image there
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/var/tmp \
    rm -rf /boot/* /run/* /var/cache/* && \
    find /var/lib -mindepth 1 -maxdepth 1 ! -name pacman -exec rm -rf {} + && \
    printf 'add_dracutmodules+=" plymouth "' | tee "/usr/lib/dracut/dracut.conf.d/40-distro.conf" && \
    KVER="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)")" && \
    depmod -a "$KVER" && \
    dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img"

LABEL containers.bootc=1

RUN bootc container lint

# Rechunk into per-package layers so unchanged packages keep identical layer digests.
# Requires `buildah build --skip-unused-stages=false` (and `-v $(pwd):/run/src` on buildah < 1.44).
FROM quay.io/coreos/chunkah AS chunkah
ARG SOURCE_DATE_EPOCH
RUN --mount=from=system-image,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        chunkah build --max-layers 128 \
          --prune /var/lib/pacman/ \
          --label containers.bootc=1 \
          --output oci:/run/src/out

FROM oci:out
