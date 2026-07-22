.PHONY: build build-no-art clean rebuild load reload

APP_IMG_NAME=datadog/datadog-security-playground
APP_IMG_TAG?=latest
APP_HOSTNAME=localhost
APP_PORT=5000
ATOMIC_RED_TEAM?=false
PLATFORM?=linux/amd64,linux/arm64
GIT_SHA?=$(shell git rev-parse HEAD 2>/dev/null || echo main)

all: build load

build:
	docker buildx build --platform $(PLATFORM) . -t $(APP_IMG_NAME):$(APP_IMG_TAG) -f app/Dockerfile --build-arg ATOMIC_RED_TEAM=$(ATOMIC_RED_TEAM) --build-arg APP_PORT=$(APP_PORT) --build-arg GIT_SHA=$(GIT_SHA) $(EXTRA_ARGS) --load

push:
	$(MAKE) build EXTRA_ARGS="--push"

build-redteam:
	$(MAKE) build ATOMIC_RED_TEAM=true APP_IMG_TAG=redteam PLATFORM=linux/amd64

clean:
	docker image rm $(APP_IMG_NAME)

rebuild: clean build

load:
	minikube image load $(APP_IMG_NAME)

reload:
	minikube image rm $(APP_IMG_NAME)
	minikube image load $(APP_IMG_NAME)

inject:
	curl -s -X POST -d "$(cmd)" http://$(APP_HOSTNAME):$(APP_PORT)/inject

ping:
	curl http://$(APP_HOSTNAME):$(APP_PORT)/ping

# AKS convenience targets
aks-deploy:
	terraform -chdir=terraform/aks apply

aks-destroy:
	terraform -chdir=terraform/aks destroy

aks-creds:
	az aks get-credentials \
		--resource-group $$(cd terraform/aks && terraform output -raw resource_group_name) \
		--name $$(cd terraform/aks && terraform output -raw cluster_name)
