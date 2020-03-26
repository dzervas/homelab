FROM jwilder/nginx-proxy:alpine

RUN { \
      echo 'ssl_client_certificate /etc/nginx/certs/default.crt;'; \
      echo 'ssl_verify_client on;'; \
    } > /etc/nginx/conf.d/client_certificates.conf
