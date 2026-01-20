.PHONY: build build-no-art clean rebuild load reload

APP_IMG_NAME=datadog/datadog-security-playground
APP_IMG_TAG?=latest
APP_HOSTNAME=localhost
APP_PORT=5000
ATOMIC_RED_TEAM?=false

all: build load

build:
	docker buildx build --platform linux/amd64,linux/arm64 . -t $(APP_IMG_NAME):$(APP_IMG_TAG) -f app/Dockerfile --build-arg ATOMIC_RED_TEAM=$(ATOMIC_RED_TEAM) --build-arg APP_PORT=$(APP_PORT) $(EXTRA_ARGS)

push:
	$(MAKE) build EXTRA_ARGS="--push"

build-redteam:
	$(MAKE) build ATOMIC_RED_TEAM=true APP_IMG_TAG=redteam

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
