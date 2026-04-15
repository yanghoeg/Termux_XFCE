#!/bin/bash
# ----------------------------------------------------------------------------------

Greeting=$(date +%H)
cat $0 | grep $Greeting | sed 's/# '$Greeting' //'
# 

# --------------------------------------------------------------------------------
# 00 Good Midnight
# 01 Good Morning
# 02 Good Morning
# 03 Good Morning
# 04 Good Morning
# 05 Good Morning
# 06 Good Morning
# 07 Good Day
# 08 Good Day
# 09 Good Day
# 10 Good Day
# 11 Good Day
# 12 Good Afternoon
# 13 Good Afternoon
# 14 Good Afternoon
# 15 Good Afternoon
# 16 Good Afternoon
# 17 Good Afternoon
# 18 Good Evening
# 19 Good Evening
# 20 Good Evening
# 21 Good Evening
# 22 Good Evening
# 23 Good Evening
