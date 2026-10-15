.PHONY: build build-no-art build-langflow-vulnerable push-langflow-vulnerable clean rebuild load reload

APP_IMG_NAME=datadog/datadog-security-playground
APP_IMG_TAG?=latest
LANGFLOW_IMG_NAME?=ghcr.io/datadog/datadog-security-playground
LANGFLOW_DDTRACE_VERSION?=4.14.0
LANGFLOW_IMG_TAG?=langflow-vulnerable-ddtrace-$(LANGFLOW_DDTRACE_VERSION)
LANGFLOW_PLATFORM?=linux/amd64
APP_HOSTNAME=localhost
APP_PORT=5000
ATOMIC_RED_TEAM?=false
PLATFORM?=linux/amd64,linux/arm64
LOCAL_PLATFORM?=linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
GIT_SHA?=$(shell git rev-parse HEAD 2>/dev/null || echo main)

all: build load

build:
	docker buildx build --platform $(LOCAL_PLATFORM) . -t $(APP_IMG_NAME):$(APP_IMG_TAG) -f app/Dockerfile --build-arg ATOMIC_RED_TEAM=$(ATOMIC_RED_TEAM) --build-arg APP_PORT=$(APP_PORT) --build-arg GIT_SHA=$(GIT_SHA) $(EXTRA_ARGS) --load

push:
	docker buildx build --platform $(PLATFORM) . -t $(APP_IMG_NAME):$(APP_IMG_TAG) -f app/Dockerfile --build-arg ATOMIC_RED_TEAM=$(ATOMIC_RED_TEAM) --build-arg APP_PORT=$(APP_PORT) --build-arg GIT_SHA=$(GIT_SHA) --push

build-langflow-vulnerable:
	docker buildx build --platform $(LANGFLOW_PLATFORM) . -t $(LANGFLOW_IMG_NAME):$(LANGFLOW_IMG_TAG) -f langflow-vulnerable/Dockerfile --build-arg GIT_SHA=$(GIT_SHA) --build-arg DDTRACE_VERSION=$(LANGFLOW_DDTRACE_VERSION) $(EXTRA_ARGS) --load

push-langflow-vulnerable:
	docker buildx build --platform $(LANGFLOW_PLATFORM) . -t $(LANGFLOW_IMG_NAME):$(LANGFLOW_IMG_TAG) -f langflow-vulnerable/Dockerfile --build-arg GIT_SHA=$(GIT_SHA) --build-arg DDTRACE_VERSION=$(LANGFLOW_DDTRACE_VERSION) --push

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
