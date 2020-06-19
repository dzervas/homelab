#!/bin/sh
docker-compose build --no-cache
docker-compose up -d
docker-compose exec octoprint bash -c "supervisorctl stop klipper && cd /klipper && make menuconfig && make && make flash FLASH_DEVICE=/dev/ttyUSB0 && supervisorctl start klipper"
