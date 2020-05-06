FROM nunofgs/octoprint

RUN apt-get update && apt-get install -y python-virtualenv virtualenv python-dev libffi-dev build-essential libncurses-dev libusb-dev avrdude gcc-avr binutils-avr avr-libc stm32flash libnewlib-arm-none-eabi gcc-arm-none-eabi binutils-arm-none-eabi
RUN echo -e '\n\
[program:klipper]\n\
command=python2 /klipper/klippy/klippy.py -l /tmp/klippy.log /data/printer.cfg\n\
stderr_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stdout_logfile_maxbytes=0\n\
stdout_logfile=/dev/stdout\n\
'>> /etc/supervisor/supervisord.conf

RUN git clone https://github.com/KevinOConnor/klipper /klipper && \
	pip install -r /klipper/scripts/klippy-requirements.txt
