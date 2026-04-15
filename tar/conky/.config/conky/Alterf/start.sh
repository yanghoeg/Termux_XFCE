#!/data/data/com.termux/files/usr/bin/bash

killall conky
sleep 1
		
conky -c .config/conky/Alterf/Alterf.conf &> /dev/null &

exit
