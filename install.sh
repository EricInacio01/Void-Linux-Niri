#!/bin/bash
# =============================================================
# instalar-niri-void.sh
# Niri + Noctalia Shell + EXT4 no Void Linux
# Baseado na instalação real de ericinacio — 29/05/2026
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $1"; }
info()   { echo -e "${BLUE}[INFO]${NC} $1"; }
titulo() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
erro()   { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# Instala apenas pacotes que ainda não estão instalados
instalar() {
    local pkgs=()
    for pkg in "$@"; do
        if xbps-query -p pkgver "$pkg" &>/dev/null; then
            warn "$pkg já instalado, pulando"
        else
            pkgs+=("$pkg")
        fi
    done
    if [ ${#pkgs[@]} -gt 0 ]; then
        sudo xbps-install -y "${pkgs[@]}"
    fi
}

# Cria symlink apenas se não existir
symlink() {
    if [ ! -e "$2" ]; then
        sudo ln -s "$1" "$2"
        log "Serviço $(basename $1) ativado"
    else
        warn "$(basename $2) já ativo"
    fi
}

# =============================================================
titulo "VERIFICAÇÕES INICIAIS"
# =============================================================

[ "$EUID" -eq 0 ] && erro "Rode como usuário normal, não root."
sudo -v 2>/dev/null || erro "Usuário sem sudo. Adicione ao grupo wheel e relogue."

USUARIO=$(whoami)
info "Usuário: $USUARIO"

# =============================================================
titulo "ETAPA 0: Repositório Noctalia"
# =============================================================

NOCTALIA_REPO="/etc/xbps.d/10-noctalia.conf"
if [ ! -f "$NOCTALIA_REPO" ]; then
    echo "repository=https://universalrepository.pages.dev/void" | \
        sudo tee "$NOCTALIA_REPO" > /dev/null
    sudo xbps-install -S
    log "Repositório Noctalia adicionado e sincronizado"
else
    warn "Repositório Noctalia já configurado"
    sudo xbps-install -S
fi

FS_TIPO=$(findmnt -n -o FSTYPE / 2>/dev/null)
if [ "$FS_TIPO" != "ext4" ]; then
    warn "Filesystem é '$FS_TIPO', não EXT4."
    read -p "Continuar mesmo assim? (s/N): " CONT
    [[ "$CONT" =~ ^[Ss]$ ]] || exit 0
else
    log "EXT4 confirmado"
fi

# =============================================================
titulo "ETAPA 1: Atualizando o sistema"
# =============================================================

sudo xbps-install -Su --yes
sudo xbps-install -Su --yes
log "Sistema atualizado"

# =============================================================
titulo "ETAPA 2: Pacotes base Wayland"
# =============================================================

instalar dbus elogind mesa mesa-vulkan-intel \
    xwayland pipewire wireplumber rtkit

# WORKAROUND: NÃO adicionar elogind ao runit — causa loop nos TTYs
symlink /etc/sv/dbus /var/service/dbus

if [ -e /var/service/elogind ]; then
    sudo rm /var/service/elogind
    warn "elogind removido do runit (evita loop nos TTYs)"
fi

sudo usermod -aG video,input,audio "$USUARIO"
log "Grupos video/input/audio ok"

# =============================================================
titulo "ETAPA 3: Niri"
# =============================================================

instalar niri

NIRI_BIN=$(which niri 2>/dev/null || echo "")
[ -z "$NIRI_BIN" ] && erro "niri não foi instalado corretamente"
log "Niri em: $NIRI_BIN"

# =============================================================
titulo "ETAPA 4: Noctalia Shell"
# =============================================================

instalar noctalia-shell
log "Noctalia Shell instalada"

# =============================================================
titulo "ETAPA 5: Aplicativos"
# =============================================================

instalar \
    alacritty nautilus \
    noto-fonts-ttf noto-fonts-emoji font-awesome6 \
    wl-clipboard grim slurp brightnessctl \
    git mako gnome-keyring \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome \
    pavucontrol NetworkManager

symlink /etc/sv/NetworkManager /var/service/NetworkManager
symlink /etc/sv/rtkit /var/service/rtkit

log "Aplicativos instalados"

# =============================================================
titulo "ETAPA 6: .bash_profile"
# =============================================================

[ -f ~/.bash_profile ] && cp ~/.bash_profile ~/.bash_profile.bak && \
    warn "Backup salvo em ~/.bash_profile.bak"

cat > ~/.bash_profile << 'BPEOF'
# .bash_profile — gerado por instalar-niri-void.sh
[ -f $HOME/.bashrc ] && . $HOME/.bashrc

export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=niri
export XDG_CURRENT_DESKTOP=niri
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# WORKAROUND: usar "niri" e NÃO "niri-session" (não existe no Void)
# WORKAROUND: espaços dentro de [ ] são obrigatórios no bash
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec niri
fi
BPEOF

log ".bash_profile configurado"

# =============================================================
titulo "ETAPA 7: Auto-login no TTY1"
# =============================================================

if [ ! -d /etc/sv/agetty-autologin-tty1 ]; then
    sudo cp -r /etc/sv/agetty-tty1 /etc/sv/agetty-autologin-tty1
    log "Serviço agetty-autologin-tty1 criado"
else
    warn "agetty-autologin-tty1 já existe"
fi

sudo tee /etc/sv/agetty-autologin-tty1/conf > /dev/null << CONFEOF
GETTY_ARGS="--noclear -a ${USUARIO}"
BAUD_RATE=38400
TERM_NAME=linux
CONFEOF
log "conf do agetty: -a $USUARIO"

[ -e /var/service/agetty-tty1 ] && sudo rm /var/service/agetty-tty1
symlink /etc/sv/agetty-autologin-tty1 /var/service/agetty-autologin-tty1

# =============================================================
titulo "ETAPA 8: Configs do Niri + Noctalia"
# =============================================================

mkdir -p ~/.config/niri/cfg
mkdir -p ~/.config/alacritty
mkdir -p ~/Imagens ~/Downloads ~/Documentos

cat > ~/.config/niri/config.kdl << 'EOF'
include "./cfg/autostart.kdl"
include "./cfg/keybinds.kdl"
include "./cfg/input.kdl"
include "./cfg/display.kdl"
include "./cfg/layout.kdl"
include "./cfg/rules.kdl"
include "./cfg/misc.kdl"
include "./cfg/animation.kdl"
EOF
log "config.kdl criado"

cat > ~/.config/niri/cfg/autostart.kdl << 'EOF'
// ────────────── Startup Applications ──────────────
    spawn-sh-at-startup "qs -c noctalia-shell"
EOF
log "autostart.kdl criado"

cat > ~/.config/niri/cfg/keybinds.kdl << 'EOF'
binds {

    // ────────────── Keybindings ──────────────

    Mod+Shift+ESCAPE                     { show-hotkey-overlay; }

    // ─── Applications ───
    Mod+Return                          hotkey-overlay-title="Open Terminal: Alacritty" { spawn "alacritty"; }

    // ─── Noctalia Bindings ───
    Mod+Space                     hotkey-overlay-title="Open App Launcher" { spawn-sh "qs -c noctalia-shell ipc call launcher toggle"; }
    Mod+ALT+L                           hotkey-overlay-title="Lock Screen" { spawn-sh "qs -c noctalia-shell ipc call lockScreen lock"; }
    Mod+Shift+Q                        hotkey-overlay-title="Session Menu" { spawn-sh "qs -c noctalia-shell ipc call sessionMenu toggle"; }
    Mod+F                               hotkey-overlay-title="File Manager: Nautilus" { spawn "nautilus"; }

    // ─── Media Controls ───
    XF86AudioRaiseVolume                allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call volume increase"; }
    XF86AudioLowerVolume                allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call volume decrease"; }
    XF86AudioMute                       allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call volume muteOutput"; }
    XF86AudioMicMute                    allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call volume muteInput"; }
    XF86AudioNext                       allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call media next"; }
    XF86AudioPrev                       allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call media previous"; }
    XF86AudioPlay                       allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call media playPause"; }
    XF86AudioPause                      allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call media playPause"; }

    // ─── Brightness ───
    XF86MonBrightnessUp                 allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call brightness increase"; }
    XF86MonBrightnessDown               allow-when-locked=true { spawn-sh "qs -c noctalia-shell ipc call brightness decrease"; }

    // ─── Window Management ───
    Mod+W                               { close-window; }
    Mod+Left                            { focus-column-left; }
    Mod+H                               { focus-column-left; }
    Mod+Right                           { focus-column-right; }
    Mod+L                               { focus-column-right; }
    Mod+Up                              { focus-window-up; }
    Mod+K                               { focus-window-up; }
    Mod+Down                            { focus-window-down; }
    Mod+J                               { focus-window-down; }
    Mod+CTRL+Left                       { move-column-left; }
    Mod+CTRL+H                          { move-column-left; }
    Mod+CTRL+Right                      { move-column-right; }
    Mod+CTRL+L                          { move-column-right; }
    Mod+CTRL+UP                         { move-window-up; }
    Mod+CTRL+K                          { move-window-up; }
    Mod+CTRL+Down                       { move-window-down; }
    Mod+CTRL+J                          { move-window-down; }
    Mod+Home                            { focus-column-first; }
    Mod+End                             { focus-column-last; }
    Mod+CTRL+Home                       { move-column-to-first; }
    Mod+CTRL+End                        { move-column-to-last; }
    Mod+Shift+Left                      { focus-monitor-left; }
    Mod+Shift+Right                     { focus-monitor-right; }
    Mod+Shift+UP                        { focus-monitor-up; }
    Mod+Shift+Down                      { focus-monitor-down; }
    Mod+Shift+CTRL+Left                 { move-column-to-monitor-left; }
    Mod+Shift+CTRL+Right                { move-column-to-monitor-right; }
    Mod+Shift+CTRL+UP                   { move-column-to-monitor-up; }
    Mod+Shift+CTRL+Down                 { move-column-to-monitor-down; }

    // ─── Workspaces ───
    Mod+WheelScrollDown                 cooldown-ms=150 { focus-workspace-down; }
    Mod+WheelScrollUp                   cooldown-ms=150 { focus-workspace-up; }
    Mod+CTRL+WheelScrollDown            cooldown-ms=150 { move-column-to-workspace-down; }
    Mod+CTRL+WheelScrollUp              cooldown-ms=150 { move-column-to-workspace-up; }
    Mod+WheelScrollRight                { focus-column-right; }
    Mod+WheelScrollLeft                 { focus-column-left; }
    Mod+CTRL+WheelScrollRight           { move-column-right; }
    Mod+CTRL+WheelScrollLeft            { move-column-left; }
    Mod+Shift+WheelScrollDown           { focus-column-right; }
    Mod+Shift+WheelScrollUp             { focus-column-left; }
    Mod+CTRL+Shift+WheelScrollDown      { move-column-right; }
    Mod+CTRL+Shift+WheelScrollUp        { move-column-left; }
    Mod+1                               { focus-workspace 1; }
    Mod+2                               { focus-workspace 2; }
    Mod+3                               { focus-workspace 3; }
    Mod+4                               { focus-workspace 4; }
    Mod+5                               { focus-workspace 5; }
    Mod+6                               { focus-workspace 6; }
    Mod+7                               { focus-workspace 7; }
    Mod+8                               { focus-workspace 8; }
    Mod+9                               { focus-workspace 9; }
    Mod+Shift+1                          { move-column-to-workspace 1; }
    Mod+Shift+2                          { move-column-to-workspace 2; }
    Mod+Shift+3                          { move-column-to-workspace 3; }
    Mod+Shift+4                          { move-column-to-workspace 4; }
    Mod+Shift+5                          { move-column-to-workspace 5; }
    Mod+Shift+6                          { move-column-to-workspace 6; }
    Mod+Shift+7                          { move-column-to-workspace 7; }
    Mod+Shift+8                          { move-column-to-workspace 8; }
    Mod+Shift+9                          { move-column-to-workspace 9; }
    Mod+TAB                             { focus-workspace-previous; }

    // ─── Layout ───
    Mod+CTRL+F                          { expand-column-to-available-width; }
    Mod+C                               { center-column; }
    Mod+CTRL+C                          { center-visible-columns; }
    Mod+T                               { toggle-window-floating; }
    Mod+Shift+F                         { fullscreen-window; }

    // ─── Screenshots ───
    Print                               { screenshot; }
    Shift+Print                         { screenshot-screen; }

    // ─── Misc ───
    Mod+ESCAPE                          allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
    CTRL+ALT+Delete                     { quit; }
    Mod+Shift+P                         { power-off-monitors; }
    Mod+O                               repeat=false { toggle-overview; }
}
EOF
log "keybinds.kdl criado"

cat > ~/.config/niri/cfg/input.kdl << 'EOF'
// ────────────── Input Configuration ──────────────
input {
    keyboard {
        xkb {
            layout "br"
            variant "abnt2"
        }
        numlock
    }

    touchpad {
        tap
        accel-speed 0.19
        accel-profile "adaptive"
        natural-scroll
        dwt
    }

    focus-follows-mouse
    workspace-auto-back-and-forth
}
EOF
log "input.kdl criado"

cat > ~/.config/niri/cfg/display.kdl << 'EOF'
// ────────────── Output Configuration ──────────────
// Descomente e ajuste conforme seu monitor:
// output "eDP-1" {
//     mode "1920x1080@60"
//     scale 1
// }
EOF
log "display.kdl criado"

cat > ~/.config/niri/cfg/layout.kdl << 'EOF'
    layout {
        gaps 0
        center-focused-column "never"
        background-color "transparent"

        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }

        focus-ring {
            off
        }

        border {
            off
        }

        struts {
        }
    }
EOF
log "layout.kdl criado"

cat > ~/.config/niri/cfg/rules.kdl << 'EOF'
    window-rule {
        geometry-corner-radius 0
        clip-to-geometry true
        open-maximized true
    }

    layer-rule {
        match namespace="^noctalia-wallpaper*"
        place-within-backdrop true
    }
EOF
log "rules.kdl criado"

cat > ~/.config/niri/cfg/misc.kdl << 'EOF'
    prefer-no-csd
    screenshot-path null

    environment {
        ELECTRON_OZONE_PLATFORM_HINT "auto"
        QT_QPA_PLATFORM "wayland"
        QT_QPA_PLATFORMTHEME "gtk3"
        QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
        XDG_CURRENT_DESKTOP "niri"
        XDG_SESSION_TYPE "wayland"
    }

    debug {
        honor-xdg-activation-with-invalid-serial
    }

    hotkey-overlay {
       skip-at-startup
    }
EOF
log "misc.kdl criado"

cat > ~/.config/niri/cfg/animation.kdl << 'EOF'
    animations {
        workspace-switch {
            spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
        }
        window-open {
            duration-ms 200
            curve "ease-out-quad"
        }
        window-close {
            duration-ms 200
            curve "ease-out-cubic"
        }
        horizontal-view-movement {
            spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
        }
        window-movement {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
        window-resize {
            spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
        }
        config-notification-open-close {
            spring damping-ratio=0.6 stiffness=1200 epsilon=0.001
        }
        screenshot-ui-open {
            duration-ms 300
            curve "ease-out-quad"
        }
        overview-open-close {
            spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
        }
    }
EOF
log "animation.kdl criado"

log "Alacritty instalado (sem config padrão — configure manualmente)"

# =============================================================
titulo "ETAPA 9: Layout do teclado no TTY"
# =============================================================

grep -q "KEYMAP" /etc/rc.conf 2>/dev/null || \
    echo 'KEYMAP="br-abnt2"' | sudo tee -a /etc/rc.conf > /dev/null
log "Layout br-abnt2 configurado"

# =============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Instalação concluída com sucesso!       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Workarounds aplicados:"
echo -e "  ${YELLOW}✓${NC} elogind fora do runit (evita loop nos TTYs)"
echo -e "  ${YELLOW}✓${NC} 'exec niri' ao invés de 'exec niri-session'"
echo -e "  ${YELLOW}✓${NC} Espaços corretos nos [ ] do .bash_profile"
echo -e "  ${YELLOW}✓${NC} Auto-login via arquivo 'conf' do agetty"
echo -e "  ${YELLOW}✓${NC} Layout br-abnt2 no TTY e no Niri"
echo -e "  ${YELLOW}✓${NC} Pacotes já instalados são ignorados"
echo -e "  ${YELLOW}✓${NC} Configs reais do Niri + Noctalia Shell instaladas"
echo ""
echo -e "${BLUE}Após reiniciar:${NC}"
echo -e "  1. O Niri já inicia com o Noctalia Shell automaticamente"
echo -e "  2. Edite ~/.config/niri/cfg/display.kdl para configurar seu monitor"
echo ""
read -p "Reiniciar agora? (s/N): " RESPOSTA
[[ "$RESPOSTA" =~ ^[Ss]$ ]] && sudo reboot || echo "Reinicie com: sudo reboot"
RL+L                          { move-column-right; }
    Mod+CTRL+UP                         { move-window-up; }
    Mod+CTRL+K                          { move-window-up; }
    Mod+CTRL+Down                       { move-window-down; }
    Mod+CTRL+J                          { move-window-down; }
    Mod+Home                            { focus-column-first; }
    Mod+End                             { focus-column-last; }
    Mod+CTRL+Home                       { move-column-to-first; }
    Mod+CTRL+End                        { move-column-to-last; }
    Mod+Shift+Left                      { focus-monitor-left; }
    Mod+Shift+Right                     { focus-monitor-right; }
    Mod+Shift+UP                        { focus-monitor-up; }
    Mod+Shift+Down                      { focus-monitor-down; }
    Mod+Shift+CTRL+Left                 { move-column-to-monitor-left; }
    Mod+Shift+CTRL+Right                { move-column-to-monitor-right; }
    Mod+Shift+CTRL+UP                   { move-column-to-monitor-up; }
    Mod+Shift+CTRL+Down                 { move-column-to-monitor-down; }

    // ─── Workspaces ───
    Mod+WheelScrollDown                 cooldown-ms=150 { focus-workspace-down; }
    Mod+WheelScrollUp                   cooldown-ms=150 { focus-workspace-up; }
    Mod+CTRL+WheelScrollDown            cooldown-ms=150 { move-column-to-workspace-down; }
    Mod+CTRL+WheelScrollUp              cooldown-ms=150 { move-column-to-workspace-up; }
    Mod+WheelScrollRight                { focus-column-right; }
    Mod+WheelScrollLeft                 { focus-column-left; }
    Mod+CTRL+WheelScrollRight           { move-column-right; }
    Mod+CTRL+WheelScrollLeft            { move-column-left; }
    Mod+Shift+WheelScrollDown           { focus-column-right; }
    Mod+Shift+WheelScrollUp             { focus-column-left; }
    Mod+CTRL+Shift+WheelScrollDown      { move-column-right; }
    Mod+CTRL+Shift+WheelScrollUp        { move-column-left; }
    Mod+1                               { focus-workspace 1; }
    Mod+2                               { focus-workspace 2; }
    Mod+3                               { focus-workspace 3; }
    Mod+4                               { focus-workspace 4; }
    Mod+5                               { focus-workspace 5; }
    Mod+6                               { focus-workspace 6; }
    Mod+7                               { focus-workspace 7; }
    Mod+8                               { focus-workspace 8; }
    Mod+9                               { focus-workspace 9; }
    Mod+Shift+1                          { move-column-to-workspace 1; }
    Mod+Shift+2                          { move-column-to-workspace 2; }
    Mod+Shift+3                          { move-column-to-workspace 3; }
    Mod+Shift+4                          { move-column-to-workspace 4; }
    Mod+Shift+5                          { move-column-to-workspace 5; }
    Mod+Shift+6                          { move-column-to-workspace 6; }
    Mod+Shift+7                          { move-column-to-workspace 7; }
    Mod+Shift+8                          { move-column-to-workspace 8; }
    Mod+Shift+9                          { move-column-to-workspace 9; }
    Mod+TAB                             { focus-workspace-previous; }

    // ─── Layout ───
    Mod+CTRL+F                          { expand-column-to-available-width; }
    Mod+C                               { center-column; }
    Mod+CTRL+C                          { center-visible-columns; }
    Mod+T                               { toggle-window-floating; }
    Mod+Shift+F                         { fullscreen-window; }

    // ─── Screenshots ───
    Print                               { screenshot; }
    Shift+Print                         { screenshot-screen; }

    // ─── Misc ───
    Mod+ESCAPE                          allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
    CTRL+ALT+Delete                     { quit; }
    Mod+Shift+P                         { power-off-monitors; }
    Mod+O                               repeat=false { toggle-overview; }
}
EOF
log "keybinds.kdl criado"

cat > ~/.config/niri/cfg/input.kdl << 'EOF'
// ────────────── Input Configuration ──────────────
input {
    keyboard {
        xkb {
            layout "br"
            variant "abnt2"
        }
        numlock
    }

    touchpad {
        tap
        accel-speed 0.19
        accel-profile "adaptive"
        natural-scroll
        dwt
    }

    focus-follows-mouse
    workspace-auto-back-and-forth
}
EOF
log "input.kdl criado"

cat > ~/.config/niri/cfg/display.kdl << 'EOF'
// ────────────── Output Configuration ──────────────
// Descomente e ajuste conforme seu monitor:
// output "eDP-1" {
//     mode "1920x1080@60"
//     scale 1
// }
EOF
log "display.kdl criado"

cat > ~/.config/niri/cfg/layout.kdl << 'EOF'
    layout {
        gaps 0
        center-focused-column "never"
        background-color "transparent"

        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }

        focus-ring {
            off
        }

        border {
            off
        }

        struts {
        }
    }
EOF
log "layout.kdl criado"

cat > ~/.config/niri/cfg/rules.kdl << 'EOF'
    window-rule {
        geometry-corner-radius 0
        clip-to-geometry true
        open-maximized true
    }

    layer-rule {
        match namespace="^noctalia-wallpaper*"
        place-within-backdrop true
    }
EOF
log "rules.kdl criado"

cat > ~/.config/niri/cfg/misc.kdl << 'EOF'
    prefer-no-csd
    screenshot-path null

    environment {
        ELECTRON_OZONE_PLATFORM_HINT "auto"
        QT_QPA_PLATFORM "wayland"
        QT_QPA_PLATFORMTHEME "gtk3"
        QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
        XDG_CURRENT_DESKTOP "niri"
        XDG_SESSION_TYPE "wayland"
    }

    debug {
        honor-xdg-activation-with-invalid-serial
    }

    hotkey-overlay {
       skip-at-startup
    }
EOF
log "misc.kdl criado"

cat > ~/.config/niri/cfg/animation.kdl << 'EOF'
    animations {
        workspace-switch {
            spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
        }
        window-open {
            duration-ms 200
            curve "ease-out-quad"
        }
        window-close {
            duration-ms 200
            curve "ease-out-cubic"
        }
        horizontal-view-movement {
            spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
        }
        window-movement {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
        window-resize {
            spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
        }
        config-notification-open-close {
            spring damping-ratio=0.6 stiffness=1200 epsilon=0.001
        }
        screenshot-ui-open {
            duration-ms 300
            curve "ease-out-quad"
        }
        overview-open-close {
            spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
        }
    }
EOF
log "animation.kdl criado"

log "Alacritty instalado (sem config padrão — configure manualmente)"

# =============================================================
titulo "ETAPA 9: Layout do teclado no TTY"
# =============================================================

grep -q "KEYMAP" /etc/rc.conf 2>/dev/null || \
    echo 'KEYMAP="br-abnt2"' | sudo tee -a /etc/rc.conf > /dev/null
log "Layout br-abnt2 configurado"

# =============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Instalação concluída com sucesso!       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Workarounds aplicados:"
echo -e "  ${YELLOW}✓${NC} elogind fora do runit (evita loop nos TTYs)"
echo -e "  ${YELLOW}✓${NC} 'exec niri' ao invés de 'exec niri-session'"
echo -e "  ${YELLOW}✓${NC} Espaços corretos nos [ ] do .bash_profile"
echo -e "  ${YELLOW}✓${NC} Auto-login via arquivo 'conf' do agetty"
echo -e "  ${YELLOW}✓${NC} Layout br-abnt2 no TTY e no Niri"
echo -e "  ${YELLOW}✓${NC} Pacotes já instalados são ignorados"
echo -e "  ${YELLOW}✓${NC} Configs reais do Niri + Noctalia Shell instaladas"
echo ""
echo -e "${BLUE}Após reiniciar:${NC}"
echo -e "  1. O Niri já inicia com o Noctalia Shell automaticamente"
echo -e "  2. Edite ~/.config/niri/cfg/display.kdl para configurar seu monitor"
echo ""
if [ ${#PKGS_AUSENTES[@]} -gt 0 ]; then
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   Pacotes não encontrados no repositório:    ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    for p in "${PKGS_AUSENTES[@]}"; do
        echo -e "  ${RED}✗${NC} $p"
    done
    echo ""
fi

read -p "Reiniciar agora? (s/N): " RESPOSTA
[[ "$RESPOSTA" =~ ^[Ss]$ ]] && sudo reboot || echo "Reinicie com: sudo reboot"
