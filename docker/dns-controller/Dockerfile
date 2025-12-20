FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir kr8s requests sniffio

WORKDIR /app

RUN useradd -u 1000 -r -s /usr/sbin/nologin user && chown -R user:user /app
USER user

COPY main.py .

CMD [ "python", "main.py" ]
