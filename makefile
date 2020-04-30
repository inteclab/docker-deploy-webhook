# Makefile for Docker Deploy Webhook
# Author: Peter Lee (peter.lee@finclab.com)
# Last update: 2020-Apr-30

env_vars=-g
export env_vars

module := docker_deploy_webhook
version?= 1.0.0

title_style='\033[3;37;40m'
no_style='\033[0m' # No Color

rebuild:
	$(MAKE) build
	$(MAKE) push
	$(MAKE) stop
	$(MAKE) start
	$(MAKE) test

start2:
	# TODO: Have the docker-compose fixed. Not working -- not sure why.
	@docker stack deploy --compose-file docker-compose.yml ${module} 

start:
	$(MAKE) start_paper
	$(MAKE) start_prod

start_paper:
	# Launch the paper service
	@docker service create \
	--name ${module}_paper \
	--with-registry-auth \
	--constraint "node.role==manager" \
	--publish=${docker_deploy_webhook_paper_port}:3000 \
	--mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
	-e PORT="3000" \
	-e CONFIG="paper" \
	-e TOKEN=${docker_deploy_webhook_paper_token} \
	-e USERNAME="$${dockerhub_username}" \
	-e PASSWORD="$${dockerhub_password}" \
    finclab/docker-deploy-webhook:latest

start_prod:
	# Launch the prod service
	@docker service create \
	--name ${module}_prod \
	--with-registry-auth \
	--constraint "node.role==manager" \
	--publish=${docker_deploy_webhook_prod_port}:3000 \
	--mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
	-e PORT="3000" \
	-e CONFIG="prod" \
	-e TOKEN=${docker_deploy_webhook_prod_token} \
	-e USERNAME="$${dockerhub_username}" \
	-e PASSWORD="$${dockerhub_password}" \
    finclab/docker-deploy-webhook:latest

stop:
	$(MAKE) stop_paper
	$(MAKE) stop_prod

stop_prod:
	@docker service rm ${module}_prod

stop_paper:
	@docker service rm ${module}_paper

shell_paper:
	@docker exec -ti ${module}_paper.1.$$(docker service ps -f 'name=${module}_paper.1' ${module}_paper -q --no-trunc | head -n1) /bin/sh

shell_prod:
	@docker exec -ti ${module}_prod.1.$$(docker service ps -f 'name=${module}_prod.1' ${module}_prod -q --no-trunc | head -n1) /bin/sh

test:
	$(MAKE) test_paper
	$(MAKE) test_prod

test_prod:
	curl -v -H "Content-Type: application/json" --data @payload.json  http://${docker_deploy_webhook_prod_url}:${docker_deploy_webhook_prod_port}/webhook/${docker_deploy_webhook_prod_token}

test_paper:
	curl -v -H "Content-Type: application/json" --data @payload.json  http://${docker_deploy_webhook_paper_url}:${docker_deploy_webhook_paper_port}/webhook/${docker_deploy_webhook_paper_token}

build:
	@docker build . --file Dockerfile --tag image
	@docker tag image finclab/docker-deploy-webhook:latest

push:
	@docker push finclab/docker-deploy-webhook:latest

deploy_old_nginx:
	@docker service create \
	--name nginx \
	--with-registry-auth \
	nginx:1.16.0

