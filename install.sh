#!/bin/bash

source config.txt

sudo apt update
sudo apt install -y python3 python3-pip redis git screen postgresql nginx certbot python3-certbot-nginx

# Install Python packages
cd gray_scheme
pip3 install -r requirements.txt
cd /root

# Configure Nginx
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    root /var/www/default/html;
    index index.html index.htm index.nginx-debian.html;

    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_pass http://localhost:7000;
    }

    location /admin/ {
        proxy_pass http://localhost:8000;
    }

    location /static/admin/ {
        proxy_pass http://localhost:8000;
    }
}

EOF
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Configure SSL certificate with Certbot
sudo certbot --nginx -d $DOMAIN

# Set up PostgreSQL database
sudo -u postgres psql -c 'create database celmond'
sudo -u postgres psql -c "create user celmond with encrypted password 'celmond'"
sudo -u postgres psql -c 'grant all privileges on database celmond to celmond'



GRAY_SCHEME_DIR="/root/gray_scheme"

update_env() {
    key=$1
    value=$2
    env_file="$GRAY_SCHEME_DIR/.env"

    if grep -q "^$key=" "$env_file"; then
        # If key exists, update its value
        sed -i "s/^$key=.*/$key=$value/" "$env_file"
    else
        # If key does not exist, add it
        echo "$key=$value" >> "$env_file"
    fi
}


update_env "bot_token" "$BOT_TOKEN"
update_env "domain" "$DOMAIN"
update_env "postgres_name" "$DB_NAME"
update_env "web_port" "$WEB_PORT_1"



if screen -list | grep -q "admin_$DOMAIN"; then
    screen -S admin_$DOMAIN  -X quit
fi

echo "
    #!/bin/bash

    cd gray_scheme

    export \$(grep -v '^#' .env | xargs) 
    echo \"USER \$1\"
    cd admin
    python3 manage.py makemigrations
    python3 manage.py makemigrations admin_panel
    python3 manage.py migrate
    export DJANGO_SUPERUSER_PASSWORD=\$3
    export DJANGO_SUPERUSER_USERNAME=\$1
    export DJANGO_SUPERUSER_EMAIL=\$2
    python3 manage.py createsuperuser --noinput
    python3 manage.py runserver localhost:8000
" > commands.sh

screen -dmS admin_$DOMAIN bash commands.sh "$ADMIN_USERNAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"

echo "Django running in a detached screen session named 'admin.'"



if screen -list | grep -q "web_bot_$DOMAIN"; then
    screen -S web_bot_$DOMAIN -X quit
fi

echo "
#!/bin/bash
cd gray_scheme
export \$(grep -v '^#' .env | xargs)
python3 main.py
" > run_bot.sh



screen -dmS web_bot_$DOMAIN bash run_bot.sh

echo "Web server and bot running in a detached screen session named 'web_bot'"

