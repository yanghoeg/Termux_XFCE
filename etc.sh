#!/data/data/com.termux/files/usr/bin/bash

export GREEN='\033[0;32m'
export TURQ='\033[0;36m'
export URED='\033[4;31m'
export UYELLOW='\033[4;33m'
export WHITE='\033[0;37m'
export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export PROOT_ROOT=$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu/root

export TERMUX_WIDGET_LINK='https://github.com/termux/termux-widget/releases/download/v0.13.0/termux-widget_v0.13.0+github-debug.apk'

# termux 셋업
termux_base_setup()
{
    set -e
    sleep 1
    echo -e "${GREEN}termux 업데이트 && 업그레이드${WHITE}"
	pkg update -y && pkg upgrade -y
    sleep 1
    #echo -e "${GREEN}termux 외부앱 허용, 진동-> 무음으로 변경.${WHITE}"
    # 기본세팅 외부앱 사용가능
    #sleep 1
    #sed -i 's/# allow-external-apps = true/allow-external-apps = true/g' /data/data/com.termux/files/home/.termux/termux.properties
    echo -e "${GREEN}진동-> 무음으로 변경.${WHITE}"
    sleep 1
    sed -i 's/# bell-character = ignore/bell-character = ignore/g' /data/data/com.termux/files/home/.termux/termux.properties

    sleep 1
    echo -e "${GREEN} alias 설정.${WHITE}"
    echo "
alias ll='ls -alhF'
alias zink='MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform '
alias shutdown='kill -9 -1'" >> $PREFIX/etc/bash.bashrc

echo '

export LANG=ko_KR.UTF-8
export LC_MONETARY="ko_KR.UTF-8"
export LC_PAPER="ko_KR.UTF-8"
export LC_NAME="ko_KR.UTF-8"
export LC_ADDRESS="ko_KR.UTF-8"
export LC_TELEPHONE="ko_KR.UTF-8"
export LC_MEASUREMENT="ko_KR.UTF-8"
export LC_IDENTIFICATION="ko_KR.UTF-8"
export LC_ALL=
export XDG_CONFIG_HOME=/data/data/com.termux/files/home/.config
export XMODIFIERS=@im=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5' >> $PREFIX/etc/bash.bashrc

    source $PREFIX/etc/bash.bashrc

    sleep 1
	echo -e "${GREEN}unzip설치.${WHITE}"
	pkg install -y unzip
  
    echo -e "${GREEN}tur-repo추가${WHITE}"
    pkg install -y tur-repo
    if ! grep -q "tur-multilib tur-hacking" ~/../usr/etc/apt/sources.list.d/tur.list; then
        sed -i 's/$/ tur-multilib tur-hacking/' ~/../usr/etc/apt/sources.list.d/tur.list
    fi

    sleep 1
    echo -e "${GREEN}x11-repo, root-repo 설치${WHITE}"
    pkg install x11-repo -y
	pkg install root-repo -y
	pkg update -y && pkg upgrade -y

    sleep 1
	echo -e "${GREEN}qt5 설치.${WHITE}"
	pkg install -y qt5*

    sleep 1
	echo -e "${GREEN}qt6 설치.${WHITE}"
	pkg install -y qt6*

    sleep 1
	echo -e "${GREEN}pavucontrol-qt 설치.${WHITE}"
	pkg install -y pavucontrol-qt

    sleep 1
    echo -e "${GREEN}xorg-server-xvfb 설치${WHITE}"
    pkg install -y xorg-server-xvfb

    sleep 1
    echo -e "${GREEN}turmux-x11-nightly 설치 ${WHITE}"
    pkg install -y termux-x11-nightly
    
    sleep 1
    echo -e "${GREEN}webp-pixbuf-loader 설치 ${WHITE}"
    pkg install -y webp-pixbuf-loader

    sleep 1
    echo -e "${GREEN}한글 설치 ${WHITE}"
    pkg install fcitx5* -y
    pkg install libhangul libhangul-static -y

    sleep 1
    echo -e "${GREEN}xfce4 나머지 설치${WHITE}"
	pkg install -y xfce4*

    sleep 1
    apt autoclean -y
    apt autoremove -y

    sleep 1
    echo -e "${GREEN}mesa-demos 설치${WHITE}"
	pkg install -y mesa-zink

    sleep 1
    echo -e "${GREEN}mesa-vulkan-icd-freedreno-dri3 설치${WHITE}"
    pkg install -y mesa-vulkan-icd-freedreno-dri3

    sleep 1
    echo -e "${GREEN}clvk 설치${WHITE}"
	pkg install -y clvk

    sleep 1
    echo -e "${GREEN}clinfo 설치${WHITE}"
	pkg install -y clinfo

    sleep 1
    echo -e "${GREEN}gtkmm4 설치${WHITE}"
	pkg install -y gtkmm4

    sleep 1
    echo -e "${GREEN}libsigc++-3.0 설치${WHITE}"
	pkg install -y libsigc++-3.0

    sleep 1
    echo -e "${GREEN} libcairomm-1.16 설치${WHITE}"
	pkg install -y libcairomm-1.16

    sleep 1
    echo -e "${GREEN} libglibmm-2.68 설치${WHITE}"
	pkg install -y libglibmm-2.68

    sleep 1
    echo -e "${GREEN} libpangomm-2.48 설치${WHITE}"
	pkg install -y libpangomm-2.48

    sleep 1
    echo -e "${GREEN} swig 설치${WHITE}"
	pkg install -y swig

    sleep 1
    echo -e "${GREEN} libpeas 설치${WHITE}"
	pkg install -y libpeas

    #sleep 1
    #echo -e "${GREEN}mesa-vulkan-icd-wrapper 설치${WHITE}"
    #echo -e "출처: https://github.com/xMeM/termux-packages/actions/runs/11801252552/artifacts/2177301700"

    #wget https://github.com/yanghoeg/Termux_XFCE/raw/main/mesa-vulkan-icd-wrapper-dbg_24.2.5-8_aarch64.deb
    #apt install -y ./mesa-vulkan-icd-wrapper-dbg_24.2.5-8_aarch64.deb
    #rm -f ./mesa-vulkan-icd-wrapper-dbg_24.2.5-8_aarch64.deb

    sleep 1
    echo -e "${GREEN}Termux-widget 설치.${WHITE}"
    wget $TERMUX_WIDGET_LINK -O termux-widget_v0.13.0+github-debug.apk
	termux-open termux-widget_v0.13.0+github-debug.apk

	echo -e "${GREEN}termux widget 설치파일 삭제.${WHITE}"
    rm termux-widget*.apk

    echo -e "${GREEN}shortcuts 생성.${WHITE}"
    mkdir ~/.shortcuts
    
echo -e '#!/data/data/com.termux/files/usr/bin/bash
killall -9 termux-x11 Xwayland pulseaudio virgl_test_server_android virgl_test_server

termux-wake-lock; XDG_RUNTIME_DIR=${TMPDIR} termux-x11 :1.0 & 
sleep 1

am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 
sleep 1

LD_PRELOAD=/system/lib64/libskcodec.so pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
LD_PRELOAD=/system/lib64/libskcodec.so pacmd load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1

#env DISPLAY=:1.0 MESA_LOADER_DRIVER_OVERRIDE=kgsl TU_DEBUG=noconform dbus-launch --exit-with-session xfce4-session &
#env DISPLAY=:1.0 MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform dbus-launch --exit-with-session xfce4-session &

env DISPLAY=:1.0 dbus-launch --exit-with-session xfce4-session &' > ~/.shortcuts/startXFCE

    chmod +x ~/.shortcuts/startXFCE

    sleep 1
    echo "$HOME/.shortcuts/startXFCE" > $PREFIX/bin/startXFCE
    chmod +x $PREFIX/bin/startXFCE
}

termux_etc_install(){
    sleep 1
    echo -e "${GREEN}firefox 설치 ${WHITE}"
    pkg install -y firefox 

    sleep 1
    echo -e "${GREEN}chromium 설치 ${WHITE}"
    pkg install -y chromium 

    sleep 1
    echo -e "${GREEN}gimp 설치 ${WHITE}"
    pkg install -y gimp 

    sleep 1
    echo -e "${GREEN}vlc-qt 설치 ${WHITE}"
    pkg install -y vlc-qt

    sleep 1
    echo -e "${GREEN}which 설치${WHITE}"
    pkg install -y which

    sleep 1
	echo -e "${GREEN}glmark2, neofetch vkmark 설치.${WHITE}"
	pkg install neofetch glmark2 vkmark -y

}

termux_hangover_wine_install()
{
    set -e
    sleep 1
    echo -e "${GREEN}tur-multilib, tur-hacking 저장소 추가${WHITE}"

    if !grep -q "tur-multilib tur-hacking" ~/../usr/etc/apt/sources.list.d/tur.list; then
        sed -i 's/$/ tur-multilib tur-hacking/' ~/../usr/etc/apt/sources.list.d/tur.list
    fi
    sleep 1

    echo -e "${GREEN}의존프로그램 설치${WHITE}"
	#pkg install -y cabextract clang 7zip freetype gnutls libandroid-shmem-static libx11 xorgproto mesa-demos libdrm libpixman libxfixes libjpeg-turbo xtrans libxxf86vm xorg-xrandr xorg-font-util xorg-util-macros libxfont2 libxkbfile libpciaccess xcb-util-renderutil xcb-util-image xcb-util-keysyms xcb-util-wm xorg-xkbcomp xkeyboard-config libxdamage libxinerama libxshmfence

    #sleep 1
    #echo -e "${GREEN}hangover-wine 설치${WHITE}"
    #pkg install -y hangover-wine

    #sleep 1
    #echo -e "${GREEN}winetricks 설치${WHITE}"
    #pkg install -y winetricks

}

termux_base_setup
termux_etc_install
#termux_hangover_wine_install
