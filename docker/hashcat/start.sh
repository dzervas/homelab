#!/usr/bin/env bash

# Wait for database to be ready
while ! mysqladmin ping -h $MYSQL_HOST --silent; do
    echo "* Waiting for database server to be up. Trying again in 5s."
    sleep 5s;
done

cd /hashview
if [ ! -f config/database.yml ]; then
    cat config/database.yml.env | envsubst > config/database.yml
fi

if [[ $(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e 'SHOW TABLES LIKE "users"' $MYSQL_DATABASE 2> /dev/null) ]]
then
    echo "* The hashview database is already initialized."
else
    echo "* Initialize the hashview database."
    RACK_ENV=production bundle exec rake db:migrate
    RACK_ENV=production bundle exec rake db:provision_defaults
    RACK_ENV=production bundle exec rake db:provision_agent
fi

# This line is needed by Docker
# to refresh or update the `config/agent_config.json`
# file from host.
cat config/agent_config.json

# Start hashview.
echo "* Starting hashview..."
RACK_ENV=production TZ=$TZ foreman start