#!/bin/sh
set -x
/home/ejbw/yealink_reboot.sh 10.10.30.33 10.10.30.38	# 260 = 00:15:65:3d:03:9c = blau = autoprov (nur dieser!)
/home/ejbw/yealink_reboot.sh 10.10.31.33 10.10.31.43	# 240 = gruen
/home/ejbw/yealink_reboot.sh 10.10.39.33 10.10.39.35	# 200 = gelb
/home/ejbw/yealink_reboot.sh 10.10.35.33 10.10.35.39	# 220 = rot
/home/ejbw/yealink_reboot.sh 127.0.0.1 172.17.2.9	# 300 = Rezeption = 172.17.2.9 = 00:15:65:37:47:8d
