# Termux_XFCE
25-11-21: 그동안 정말정말 바빠서 방치되었는데 재미나이와 힘을 합쳐서 최대한 빨리 모던하게 수정하겠습니다.

https://github.com/phoenixbyrd/Termux_XFCE/tree/main의 debian proot에서 ubuntu proot로 변경하였습니다.
이외 fcitx5-hangul 등의 설치를 추가하였습니다.
현재 xfce4 배경화면 변경에 오류가 있어 phoenixbyrd님이 올려주신 임시 스크립트를 사용해야합니다.
temp_background.sh를 실행한 후 배경화면 번호를 입력하면 됩니다.

저는 갤럭시 폴드6(스냅드래곤8 gen3) 갤럭시탭 s9 울트라(스냅드래곤8 gen2)를 사용하고 있습니다.
이 스크립트에는 mesa가 설치됩니다. 
만약 zenity가 실행되지 않으면 mesa-zink 설치 후 zenity 사용하고 다시 mesa를 설치하세요 ㅠ
(mesa-zink를 설치하면 가속이 되지 않습니다.)

termux-native 가속 드라이버는 아래 url에서 다운받을 수 있습니다.
https://github.com/xMeM/termux-packages
위 url로 접속하여 actions -> runs에서 mesa-vulkan-icd-wrapper와 mesa관련 드라이버를 설치하면 됩니다.

추후 스냅드래곤8 gen3이 안정화 되면 스크립트를 업데이트 하겠습니다.

추가:
이 스크립트를 사용해주셔서 감사합니다. 혹시 스크립트에 오류가 있거나 더 좋은 아이디어가 있으면 풀리퀘스트도 해주세요(한번 받아보고 싶어요).


# Install

전체 프로그램 설치: 아래 명령어를 입력하세요

```
curl -sL https://raw.githubusercontent.com/yanghoeg/Termux_XFCE/main/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```
&nbsp;
 

&nbsp;

# 데스크탑을 사용하세요
  
Termux에서  ```startXFCE``` 를 입력하세요.
  
이 명령어는 termux-x11 server, XFCE4 desktop and open the Termux-X11 app right into the desktop. 

To enter the ubuntu proot install from terminal use the command ```ubuntu```

Also note, you do not need to set display in ubuntu proot as it is already set. This means you can use the terminal to start any GUI application and it will startup.

&nbsp;

# Hardware Acceleration & Proot

Here are some aliases prepared to make launching things just a little easier.

Termux XFCE:

zink - Launch apps in ubuntu proot with hardware acceleration


ubuntu proot:

zink - Launch apps in ubuntu proot with hardware acceleration
   
To enter proot use the command ```ubuntu```, from there you can install aditional software with apt and use cp2menu in termux to copy the menu items over to termux xfce menu. 


&nbsp;

설치시 2개의 명령어를 사용할 수 있습니다.
  
```prun```  prun [명령어] 형태로 termux 터미널에서 우분투 프로그램을 실행할 수 있습니다.
  
```cp2menu``` Running this will pop up a window allowing you to copy .desktop files from ubuntu proot into the termux xfce "start" menu so you won't need to launch them from terminal. A launcher is available in the System menu section.

&nbsp;

# Process completed (signal 9) - press Enter

install LADB from playstore or from here https://github.com/hyperio546/ladb-builds/releases

connect to wifi   
  
In split screen have one side LADB and the other side showing developer settings.
  
In developer settings, enable wireless debugging then click into there to get the port number then click pair device to get the pairing code.
  
Enter both those values into LADB
  
Once it connects run this command
  
```adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"```

You can also run adb shell from termux directly by following the guide found in this video

[https://www.youtube.com/watch?v=BHc7uvX34bM](https://www.youtube.com/watch?v=BHc7uvX34bM)
