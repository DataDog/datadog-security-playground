.PHONY: build clean rebuild load reload

APP_IMG_NAME=datadog/datadog-security-playground:latest

all: build load

build:
	docker build . -t $(APP_IMG_NAME) -f app/Dockerfile

clean:
	docker image rm $(APP_IMG_NAME)

rebuild: clean build

load:
	minikube image load $(APP_IMG_NAME)

reload:
	minikube image rm $(APP_IMG_NAME)
	minikube image load $(APP_IMG_NAME)
