#!/bin/bash

COMMAND=$1

function parseRepoSshUrl()
{
    local re="^git\@(\S+)\:(\S+)\/(\S+)\.git"

    if [[ $1 =~ $re ]]
        then
            local host="${BASH_REMATCH[1]}"
            local vendor="${BASH_REMATCH[2]}"
            local project="${BASH_REMATCH[3]}"

            echo "$project $(buildRepoSshUrl "$host" "$vendor" "$project")";
        else
            echo '0 0' 
        fi
}
function parseRepoWebUrl()
{
    local re="https\:\/\/([-a-z0-9\.]+)\/([-a-z0-9\_]+)\/([-a-z0-9\_]+)\/?"

    if [[ $1 =~ $re ]]
        then
            local host="${BASH_REMATCH[1]}"
            local vendor="${BASH_REMATCH[2]}"
            local project="${BASH_REMATCH[3]}"

            echo "$project $(buildRepoSshUrl "$host" "$vendor" "$project")";
        else
            echo '0 0' 
        fi

}
function buildRepoSshUrl() {
    echo "git@${1}:${2}/${3}.git";
}
function errorMessage() {
    echo -e "\e[93m\e[101m$1\e[49m\e[39m\n"
}
function parseRepoUrl()
{
    if [[ $1 == "https"* ]]; then
        echo $(parseRepoWebUrl "$1");

    elif [[ $1 == "git@"* ]]; then
        echo $(parseRepoSshUrl "$1");
    else
        echo '0 0' 
    fi
}
function runCommandDeploy()
{
    local repo_url=$1
    local branch="${2:-master}"

    # Parse repository ssh URL
    read project ssh_url < <(parseRepoUrl "$repo_url")

    if [[ $ssh_url == "0" ]]; then
        errorMessage "Invalid Repository URL"
        exit 1;
    fi

    # Clone repository
    
    project_dir="./${project}-${branch}"
    #git clone $ssh_url $project_dir || { errorMessage "Failed to clone the repository" ; exit 1; }

    # Start a new stack

    cd "${project_dir}/.docker" || { errorMessage "Deploy failed" ; exit 1; }

    cat .env | awk "{ print gensub(/COMPOSE_PROJECT_NAME\=(\S+)/, \"COMPOSE_PROJECT_NAME=\\\1-$branch\", \"g\", \$1);}" > .env_tmp
    cp .env_tmp .env
    rm .env_tmp

    if [[ ! $xdev_dev_mode == "1" ]]; then
        docker-compose up -d --build || { errorMessage "Deploy failed" ; exit 1; } 
    else
        #docker-compose up build -f docker-compose.yml -f docker-compose.xdev.yml -d --build || { errorMessage "Deploy failed" ; exit 1; } 
        docker-compose -f docker-compose.yml -f docker-compose.xdev.yml up -d --build || { errorMessage "Deploy failed" ; exit 1; } 
    fi
   
    # Deploy the repository
    docker-compose exec -u xcdocker -e "XDEV_CMD_DEPLOY=Y" -e "XDEV_CMD_DEPLOY_ARG_BRANCH=${branch}" workspace bash
}
function runCommandBash()
{
  cd ".docker" || { errorMessage "Docker stack not found" ; exit 1; }

  if [ -z `docker ps -q --no-trunc | grep $(docker-compose ps -q workspace)` ]; then
    docker-compose up -d
  fi

  docker-compose exec -u xcdocker workspace bash
}
function runCommandAddKey()
{
  DIR=$(dirname "${1}")
  FILE=$(basename "${1}")
  echo $DIR;
  echo $FILE;
  docker run --rm -v $DIR:/source -v x-service-shared:/dest -w /source alpine /bin/sh -c "cp $FILE /dest ;chown 1000:1000 /dest/$FILE" || { errorMessage "Failed to add key $1" ; exit 1; } 
  
  echo  -e "\e[32mAdded key\e[39m $1"
}

#Load config file
CFG_FILE=~/xc.conf

if test -f "$CFG_FILE"; then
    _IFS=$IFS
    IFS="="
    i=0
    while read -r var value
    do
        ((i=i+1))
        export "$var"="$value"
    done < $CFG_FILE || { errorMessage "Failed to load config file. Parse error on line $i" ; exit 1; } 
    IFS=$_IFS
else
    touch $CFG_FILE
    printf "xdev_dev_mode=0\n" > $CFG_FILE
fi

if [[ $COMMAND == "help" || $COMMAND == "" ]]; then
    echo -e "usage: xc <command> <args>

Commands:

    \e[32mdeploy\e[39m <repoUrl> <branch>  Deploys the repository to the local machine
    \e[32madd-key\e[39m <keyFile>          Adds new private key to docker's shared volume
"
    exit 0
fi

if [[ $COMMAND == "deploy" ]]; then
    runCommandDeploy $2 $3
elif [[ $COMMAND == "add-key" ]]; then
    runCommandAddKey $2
elif [[ $COMMAND == "bash" ]]; then
    runCommandBash
else
    errorMessage "Invalid command"
    exit 127;
fi

