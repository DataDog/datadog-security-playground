.PHONY: all clean rebuild help

docker-build-assets:
	@echo "Building Docker build image for assets..."
	docker build --progress=plain -t datadog-security-playground-assets:latest -f Dockerfile .
	@echo "Extracting binaries from Docker image..."
	@docker create --name temp-assets datadog-security-playground-assets:latest
	@docker cp temp-assets:/output/bpfdoor/fake-bpfdoor.x64 ./bpfdoor/ || true
	@docker cp temp-assets:/output/malware/malware.x64 ./malware/ || true
	@docker cp temp-assets:/output/malware/malware.arm64 ./malware/ || true
	@docker rm temp-assets
	@echo "Binaries extracted successfully!"
	@ls -lh bpfdoor/*.x64 rce-malware/malware.*

# Default target
all: docker-build-assets

docker-clean:
	@echo "Cleaning Docker images..."
	@docker rmi datadog-security-playground-assets:latest 2>/dev/null || true

clean: docker-clean

# Force rebuild
rebuild: clean all

# Help target
help:
	@echo "Datadog Security Playground Assets Build System"
	@echo ""
	@echo "make all                 - Build all binaries using Docker (default)"
	@echo "make clean               - Delete Docker image"
	@echo "make rebuild             - Force clean and rebuild"
	@echo "make help                - Show this help message"
