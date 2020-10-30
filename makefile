# Makefile for Docker Deploy Webhook
# Author: Peter Lee (peter.lee@finclab.com)
# Last update: 2020-Apr-30

# labenv=dev, or anything else
	# All other commands

# labenv=paper
	# make start labenv=paper  # deploy to docker swarm paper
	# make stop  labenv=paper  # stop service in docker swarm paper

# labenv=prod
	# make start labenv=prod  # deploy to docker swarm prod
	# make stop  labenv=prod  # stop service in docker swarm prod

env_vars=-g
export env_vars

############################## Env Variables ##############################
# Supported lab environment: prod, paper (do not deploy), any others (for local dev)
labenv ?= dev

stack := docker_deploy
service := webhook
version := $(shell git describe --tags --always)

# Docker Reigistry - Github Packages Registry: <org_name>/<repo_name>/<image_name>
docker_registry ?= docker.pkg.github.com/inteclab/docker-deploy-webhook
docker_image := $(docker_registry)/$(stack)

title_style='\033[3;37;40m'
no_style='\033[0m' # No Color
makefile_path := $(abspath $(lastword $(MAKEFILE_LIST)))

ifeq ($(labenv), prod)
docker_exec_cmd := @docker exec -ti ${labenv}_${stack}_${service}.1.$$(docker service ps -f 'name=${labenv}_${stack}_${service}.1' ${labenv}_${stack}_${service} -q --no-trunc | head -n1)
endif
ifeq ($(labenv), paper)
docker_exec_cmd := @docker exec -ti ${labenv}_${stack}_${service}.1.$$(docker service ps -f 'name=${labenv}_${stack}_${service}.1' ${labenv}_${stack}_${service} -q --no-trunc | head -n1)
endif
ifeq ($(labenv), dev)
docker_exec_cmd := @docker container exec -it ${labenv}_${stack}
endif

############################## General ##############################
rebuild:
	$(MAKE) build
	$(MAKE) push
	$(MAKE) stop
	$(MAKE) start
	# $(MAKE) test

restart:
	# Restart both prod and paper
	docker service rm prod_${stack}_${service}
	docker service rm paper_${stack}_${service}
	sleep 3
	$(MAKE) start_paper labenv=paper
	$(MAKE) start_prod labenv=prod

start:
	@echo "\n${title_style}Starting ${stack} (${labenv}) Service (${service})...${no_style}\n"
ifeq ($(labenv), prod)
	$(MAKE) start_prod
endif
ifeq ($(labenv), paper)
	$(MAKE) start_paper
endif
ifeq ($(labenv), dev)
	# Generate the gpg password secret file (as Docker external secret is swarm only)
	# echo $${github_gpg_password} > ./docker/GPG_PASSWORD.secret
	# Launch the service
	@docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
	# Remove the secret
	# rm ./docker/GPG_PASSWORD.secret
endif

stop:
	# Stop the DataLab service
	@echo "\n${title_style}Stopping ${stack} (${labenv}) Service...${no_style}\n"
ifeq ($(labenv), prod)
	$(MAKE) stop_swarm_service
endif
ifeq ($(labenv), paper)
	$(MAKE) stop_swarm_service
endif
ifeq ($(labenv), dev)
	docker-compose -f docker-compose.yml down --remove-orphans
	sleep 2
endif

test:
	# init a test package
	@echo "\n${title_style}Testing ${stack} (${labenv}) Service...${no_style}\n"
ifeq ($(labenv), prod)
	$(MAKE) test_prod
endif
ifeq ($(labenv), paper)
	$(MAKE) test_paper
endif
ifeq ($(labenv), dev)
	echo "NOT IMPLEMENTED"
endif

test_prod:
	# curl -v -H "Content-Type: application/json" --data "{ \"push_data\": { \"tag\": \"prod\" }, \"repository\": { \"repo_name\": \"docker.pkg.github.com/inteclab/datastore/timescaledb\" }}" http://${docker_deploy_webhook_prod_url}:${docker_deploy_webhook_prod_port}/webhook/${docker_deploy_webhook_prod_token}
	curl -v -H "Content-Type: application/json" --data "{ \"push_data\": { \"tag\": \"prod\" }, \"repository\": { \"repo_name\": \"docker.pkg.github.com/inteclab/datalab/databot\" }}" http://${docker_deploy_webhook_prod_url}:${docker_deploy_webhook_prod_port}/webhook/${docker_deploy_webhook_prod_token}

test_paper:
	curl -v -H "Content-Type: application/json" --data "{ \"push_data\": { \"tag\": \"latest\" }, \"repository\": { \"repo_name\": \"docker.pkg.github.com/inteclab/datastore/timescaledb\" }}" http://${docker_deploy_webhook_paper_url}:${docker_deploy_webhook_paper_port}/webhook/${docker_deploy_webhook_paper_token}

build:
	# Pull remote changes to the `prod` branch of submodules (i.e. `finclab`)
	git submodule update --remote
	docker build . --file ./Dockerfile --tag ${stack}:dev

push:
ifeq ($(labenv), paper)
	docker tag ${stack}:dev ${docker_image}:latest
	docker image push ${docker_image}:latest
endif
ifeq ($(labenv), prod)
	docker tag ${stack}:dev ${docker_image}:${labenv}
	docker image push ${docker_image}:${labenv}
endif

############################## Paper/Prod Environment  Specifics ##############################
start_paper:
	@echo "\n${title_style}Deploying ${stack} to Swarm...${no_style}\n"
	# Launch the paper service
	@docker service create \
    --name ${labenv}_${stack}_${service} \
	--with-registry-auth \
	--constraint "node.role==manager" \
	--publish=${docker_deploy_webhook_paper_port}:3000 \
	--mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
	-e PORT="3000" \
	-e CONFIG="paper" \
	-e TOKEN=${docker_deploy_webhook_paper_token} \
	-e REGISTRY="docker.pkg.github.com" \
	-e USERNAME="$${github_username}" \
	-e PASSWORD="$${github_access_token}" \
	docker.pkg.github.com/inteclab/docker-deploy-webhook/docker_deploy:latest

start_prod:
	@echo "\n${title_style}Deploying ${stack} to Swarm...${no_style}\n"
	# Launch the prod service
	@docker service create \
    --name ${labenv}_${stack}_${service} \
	--with-registry-auth \
	--constraint "node.role==manager" \
	--publish=${docker_deploy_webhook_prod_port}:3000 \
	--mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
	-e PORT="3000" \
	-e CONFIG="prod" \
	-e TOKEN=${docker_deploy_webhook_prod_token} \
	-e REGISTRY="docker.pkg.github.com" \
	-e USERNAME="$${github_username}" \
	-e PASSWORD="$${github_access_token}" \
	docker.pkg.github.com/inteclab/docker-deploy-webhook/docker_deploy:prod

stop_swarm_service:
	# Stop the service in Docker Swarm, service name: i.e. datalab_prod_datalab
	# Syntax: make stop_swarm_service labenv=prod
	@echo "\n${title_style}Removing ${stack} (${labenv}) Service from Docker Swarm...${no_style}\n"
	docker stack rm ${labenv}_${stack}_${service} | true
	docker service rm ${labenv}_${stack}_${service} | true

shell:
	@${docker_exec_cmd} /bin/bash

exec:
	# Syntax: make exec labenv=prod cmd="touch /tmp/example"
	@${docker_exec_cmd} ${cmd}

log:
	@docker service logs ${labenv}_${stack}_${service} -f

#shell_paper:
#	@docker exec -ti ${stack}_paper.1.$$(docker service ps -f 'name=${stack}_paper.1' ${stack}_paper -q --no-trunc | head -n1) /bin/sh
#
#shell_prod:
#	@docker exec -ti ${stack}_prod.1.$$(docker service ps -f 'name=${stack}_prod.1' ${stack}_prod -q --no-trunc | head -n1) /bin/sh
#
