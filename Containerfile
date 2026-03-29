FROM scratch AS ctx

FROM ghcr.io/ohaiibuzzle/cachy-bootc:latest AS base

FROM base AS aur-builder

RUN pacman -Sy --noconfirm base-devel sudo git && \
    useradd builder && \
    echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir /built_pkgs/

WORKDIR /tmp

RUN sudo -u builder git clone https://aur.archlinux.org/libfprint-cs9711-git.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \ 
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

RUN sudo -u builder git clone https://aur.archlinux.org/visual-studio-code-bin.git package && \
    cd package && \
    sudo -u builder makepkg -s --noconfirm && \ 
    cp *.tar.zst /built_pkgs/ && \
    cd ../ && rm -rf package

FROM base AS system

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    7zip ark amd-ucode base base-devel bash-completion btop btrfs-progs \
    cpio dbus dbus-glib discover distrobox dolphin dosfstools dracut \
    e2fsprogs efibootmgr fcitx5-anthy fcitx5-im fcitx5-unikey firefox flatpak \
    flatpak-kcm gamescope-session-cachyos git glib2 gptfdisk \
    intel-ucode jq just kate kwalletmanager linux-cachyos \
    linux-cachyos-nvidia-open linux-firmware mangohud man-db mpv nano \
    networkmanager noto-fonts noto-fonts-cjk noto-fonts-extra \
    nvtop opencl-mesa opencl-nvidia openssh ostree partitionmanager \
    pipewire pipewire-jack plasma plasma-login-manager \
    plasma-systemmonitor plymouth plymouth-kcm podman \
    power-profiles-daemon sbctl shadow skopeo starship \
    steam-devices tailscale tlp vulkan-radeon wireplumber \
    xfsprogs yakuake zram-generator

# Copy packages from AUR Builder
RUN mkdir /tmp/built_pkgs
COPY --from=aur-builder /built_pkgs/ /tmp/built_pkgs/

# We need /opt to not be a symlink during package installation
RUN rm -rf /opt && \
    ls /tmp/built_pkgs && \
    pacman -U --noconfirm /tmp/built_pkgs/*.tar.zst && \
    rm -rf /tmp/built_pkgs && \
    mv /opt /usr && mkdir /opt

# Install fprintd here after CS9311 was installed
RUN pacman -S --noconfirm fprintd

# Cleanup
COPY build_files/ /

RUN pacman -Scc --noconfirm && \
    echo -e "en_US.UTF-8 UTF-8\nen_GB.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && \
    echo -e '\neval $(starship init bash)' >> /etc/bash.bashrc && \
    plymouth-set-default-theme bgrt && \
    systemctl enable NetworkManager power-profiles-daemon bluetooth plasmalogin tlp opt.mount && \
    mkdir -p /usr/lib/bootc/kargs.d/ && \
    echo 'kargs = ["quiet splash zswap.enabled=0"]' > /usr/lib/bootc/kargs.d/00-splash.toml && \
    echo 'Error "UCM support temporary disabled for ${CardLongName}"' >> /usr/share/alsa/ucm2/USB-Audio/Sony/DualSense-PS5.conf


# https://github.com/bootc-dev/bootc/issues/1801
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    printf 'add_dracutmodules+=" plymouth "' | tee "/usr/lib/dracut/dracut.conf.d/40-distro.conf" && \
    dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img"

LABEL containers.bootc 1

RUN bootc container lint