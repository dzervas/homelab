# Got from https://github.com/hadim/docker-hashview
FROM ruby:2.4

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gettext-base \
    curl \
    git \
    wget \
    nano \
    openssl \
    p7zip-full \
    mariadb-client \
    redis-server

ENV HASHVIEW_VERSION=master
ENV HASHCAT_VERSION=5.1.0
ENV MYSQL_HOST=mysql
ENV MYSQL_PORT=3306
ENV MYSQL_USER=root
ENV MYSQL_PASSWORD=changeme
ENV MYSQL_DATABASE=hashview

# Install hashview
RUN git clone --depth 1 --branch $HASHVIEW_VERSION https://github.com/hashview/hashview /hashview && rm -rf /hashview/.git
RUN cd /hashview && rm Gemfile.lock && gem install bundler && bundle install

COPY database.yml /hashview/config/database.yml.env
COPY agent_config.json /hashview/config/agent_config.json

# Install hashcat
RUN wget https://hashcat.net/files/hashcat-${HASHCAT_VERSION}.7z -O /tmp/hashcat.7z && \
    7z x /tmp/hashcat.7z -o/ && \
    rm /tmp/hashcat.7z && \
    ln -s /hashcat-${HASHCAT_VERSION} /hashcat

# Apply redis patch in Rakefile - I don't think they take MRs anymore...
RUN echo "require 'redis/errors'" | cat - /hashview/Rakefile > /tmp/Rakefile && \
    mv /tmp/Rakefile /hashview/Rakefile

# FFS Why am I running this piece of shit
RUN sed -i "s/SSLEnable: true/SSLEnable: false/" /hashview/helpers/sinatra_ssl.rb && \
    sed -i "s/SSL[CP].*//" /hashview/helpers/sinatra_ssl.rb && \
    sed -i "s/https/http/g" /hashview/jobs/background_worker.rb /hashview/routes/hub.rb

EXPOSE 4567

WORKDIR /hashview
#USER nobody:nogroup

COPY start.sh /start.sh
CMD bash /start.sh