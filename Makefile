.PHONY: build clean rebuild load reload

PHPAPP_IMG_NAME=datadog/datadog-security-playground:latest

all: build load

build:
	docker build . -t $(PHPAPP_IMG_NAME) -f app/Dockerfile

clean:
	docker image rm $(PHPAPP_IMG_NAME)

rebuild: clean build

load:
	minikube image load $(PHPAPP_IMG_NAME)

reload:
	minikube image rm $(PHPAPP_IMG_NAME)
	minikube image load $(PHPAPP_IMG_NAME)
