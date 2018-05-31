#!/usr/bin/env bash

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root, please run sudo or log in as root first." 1>&2
    exit 1
  fi
}

check_linux_memory() {
  echo `free -g --si | awk ' /Mem:/  {print $2} '`
}

check_docker () {
  docker_path=`which docker.io || which docker`
  if [ -z $docker_path ]; then
    read  -p "Docker not installed. Hit enter to install from https://get.docker.com/ or type Ctrl+C to exit"
    curl https://get.docker.com/ | sh
  fi
  docker_path=`which docker.io || which docker`
  if [ -z $docker_path ]; then
    echo Installing Docker failed. Exiting.
    exit
  fi
}

check_docker_compose () {
  docker_path=`which docker-compose`
  if [ -z $docker_path ]; then
    read  -p "Docker Compose not installed. Hit enter to install or type Ctrl+C to exit"
    curl -s -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo `docker-compose --version`
    echo ""
  fi
  docker_path=`which docker.io || which docker`
  if [ -z $docker_path ]; then
    echo Installing Docker failed. Exiting.
    exit
  fi
}

check_disk_and_memory() {
  mem_free=$(check_linux_memory)

  if [ "$mem_free" -lt 1 ]; then
    echo "WARNING: MIMO requires 1GB RAM. This system doesn't have"
    echo "sufficient memory."
    echo
    echo "Please provision a server with at least 1GB RAM"
    exit 1
  fi

  free_disk="$(df /var | tail -n 1 | awk '{print $4}')"
  if [ "$free_disk" -lt 5000 ]; then
    echo "WARNING: MIMO requires at least 5GB free disk space. This system"
    echo "doesn't have enough disk space."
    echo
    echo "Please free up some space or expand your disk before continuing."
    echo
    exit 1
  fi
}

check_port() {
  if lsof -Pi :${1} -sTCP:LISTEN -t >/dev/null; then
    echo ${1} is in use
    echo "Please ensure you stop any services that are running on port ${1}"
    exit 1
  fi
}

check_config_exists() {
  FILE='production.vars'
  if [ ! -f $FILE ]; then
    echo "File $FILE does not exist. Creating from defaults"
    cp $FILE.orig $FILE
  fi
}

check_ports() {
  check_port "80"
  check_port "443"
}

find_in_file() {
  val=`sed -n -e "s/${1}=//p" production.vars`
  echo "$val"
}

update_config() {

  local ok_config='no'
  local production_config='production.vars'
  local changelog='change.log'

  hostname=`find_in_file MIMO_DOMAIN`
  hostname_orig=`find_in_file MIMO_DOMAIN`

  admin_user=`find_in_file MIMO_ADMIN_USER`
  admin_user_orig=$admin_user

  smtp_host=`find_in_file MIMO_SMTP_HOST`
  smtp_host_orig=$smtp_host

  smtp_port=`find_in_file MIMO_SMTP_PORT`
  smtp_port_orig=$smtp_port

  smtp_user=`find_in_file MIMO_SMTP_USER`
  smtp_user_orig=$smtp_user

  smtp_pass=`find_in_file MIMO_SMTP_PASS`
  smtp_pass_orig=$smtp_pass

  smtp_domain_orig=`find_in_file MIMO_SMTP_DOMAIN`
  dashboard_url=`find_in_file MIMO_DASHBOARD_URL`
  api_url=`find_in_file MIMO_API_URL`

  while [[ "$ok_config" == "no" ]]
  do
    if [ ! -z "$hostname" ]
    then
      read -p "What's the domain for your MIMO installation? [$hostname]: " new_value
      if [ ! -z "$new_value" ]
      then
        hostname="$new_value"
      fi
      if [[ ! $hostname =~ ^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$ ]]
      then
        echo
        echo "[WARNING!!!] MIMO needs a valid hostname. IP addresses are not supported!"
        echo ""
        echo "A valid hostname should look like 'example.com' and not 'test.example.com'"
        echo "Setting your hostname to example.com"
        echo
        hostname="example.com"
      fi
    fi

    if [ ! -z "$admin_user" ]
    then
      read -p "Enter your admin email, this will be your master login? [$admin_user]: " new_value
      if [ ! -z "$new_value" ]
      then
        admin_user="$new_value"
      fi
      if [[ ! $admin_user =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]
      then
        echo
        echo "[WARNING!!!] MIMO needs a valid email, please try again!"
        echo
        admin_user="user@example.com"
      fi
    fi

    if [ ! -z "$smtp_host" ]
    then
      read -p "Enter your SMTP hostname [$smtp_host]: " new_value
      if [ ! -z "$new_value" ]
      then
        smtp_host="$new_value"
      fi
      if [ "$smtp_host" == "smtp.sendgrid.net" ]
      then
        smtp_port=2525
      fi
      if [ "$smtp_address" == "smtp.mailgun.org" ]
      then
        smtp_port=587
      fi
    fi

    if [ ! -z "$smtp_port" ]
    then
      read -p "Enter your SMTP port [$smtp_port]: " new_value
      if [ ! -z "$new_value" ]
      then
        smtp_port="$new_value"
      fi
    fi

    if [ ! -z "$smtp_user" ]
    then
      read -p "Enter your SMTP username [$smtp_user]: " new_value
      if [ ! -z "$new_value" ]
      then
        smtp_user="$new_value"
      fi
    fi

    if [ ! -z "$smtp_pass" ]
    then
      read -p "Enter your SMTP password [$smtp_pass]: " new_value
      if [ ! -z "$new_value" ]
      then
        smtp_pass="$new_value"
      fi
    fi

    echo -e "\nDoes this look right?\n"
    echo "Hostname      : $hostname"
    echo "Admin Email   : $admin_user"
    echo "SMTP Host     : $smtp_host"
    echo "SMTP Port     : $smtp_port"
    echo "SMTP User     : $smtp_user"
    echo "SMTP Password : $smtp_pass"
    echo ""
    read -p "Hit ENTER to continue. Type 'no' to try again. Ctrl+C will exit: " ok_config

    echo "Writing configs to $production_config. Then we'll start the magic"

    postgres_pass=`find_in_file POSTGRES_PASSWORD`
    rails_secret=`find_in_file RAILS_SECRET_KEY`
    admin_user=`find_in_file MIMO_ADMIN_USER`

    # cp $production_config.orig $production_config
    cp $production_config $production_config.backup

    sed -i -e "s/MIMO_DOMAIN=${hostname_orig}/MIMO_DOMAIN=$hostname/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${hostname} as primary domain"
      rm $changelog
    fi

    sed -i -e "s~MIMO_DASHBOARD_URL=${dashboard_url}~MIMO_DASHBOARD_URL=https://dashboard.$hostname~w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added https://dashboard.${hostname} as dashboard url"
      rm $changelog
    fi

    sed -i -e "s~MIMO_API_URL=${api_url}~MIMO_API_URL=https://api.$hostname~w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added https://api.${hostname} as API url"
      rm $changelog
    fi

    sed -i -e "s/MIMO_SMTP_HOST=${smtp_host_orig}/MIMO_SMTP_HOST=$smtp_host/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${smtp_host} as SMTP hostname"
      rm $changelog
    fi

    sed -i -e "s/MIMO_SMTP_PORT=${smtp_port_orig}/MIMO_SMTP_PORT=$smtp_port/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${smtp_port} as SMTP port"
      rm $changelog
    fi

    sed -i -e "s/MIMO_SMTP_USER=${smtp_user_orig}/MIMO_SMTP_USER=$smtp_user/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${smtp_user} as SMTP user"
      rm $changelog
    fi

    sed -i -e "s/MIMO_SMTP_PASS=${smtp_pass_orig}/MIMO_SMTP_PASS=$smtp_pass/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${smtp_pass} as SMTP pass"
      rm $changelog
    fi

    sed -i -e "s/MIMO_SMTP_DOMAIN=${smtp_domain_orig}/MIMO_SMTP_DOMAIN=$hostname/w $changelog" $production_config
    if [ -s $changelog ]
    then
      echo "Added ${hostname} as SMTP domain"
      rm $changelog
    fi

    if [ "$admin_user" == "USER" ] ; then
      sed -i -e "s/MIMO_ADMIN_USER=USER/MIMO_ADMIN_USER=$admin_user/w $changelog" $production_config
      if [ -s $changelog ]
      then
        echo "Added ${admin_user} as admin user"
        rm $changelog
      fi
    fi

    if [ "$rails_secret" == "KEY" ] ; then
      rails_secret=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
      sed -i -e "s/RAILS_SECRET_KEY=KEY/RAILS_SECRET_KEY=$rails_secret/w $changelog" $production_config

      if [ -s $changelog ]
      then
        echo "Updated RAILS SECRET"
        rm $changelog
      fi
    else
      echo 'Not updating secret token'
    fi

    if [ "$postgres_pass" == "PASS" ] ; then
      postgres_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
      sed -i -e "s/POSTGRES_PASSWORD=PASS/POSTGRES_PASSWORD=$postgres_pass/w $changelog" $production_config

      if [ -s $changelog ]
      then
        echo "Updated postgres password"
        rm $changelog
      fi
    else
      echo 'Not updating postgres password'
    fi

    docker-compose down && docker-compose build && docker-compose -f docker-compose.yml -f docker-compose.prod.yml up
  done
}

check_root
check_docker
check_docker_compose
check_disk_and_memory
check_ports
check_config_exists
update_config