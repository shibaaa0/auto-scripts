#! /bin/sh
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep capacity | cut -d ':' -f2 | xargs