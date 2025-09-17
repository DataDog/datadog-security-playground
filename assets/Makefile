.PHONY: all clean fake-bpfdoor malware

all: fake-bpfdoor malware

fake-bpfdoor:
	@echo "Building fake-bpfdoor binary..."
	cd fake-bpfdoor && make

malware:
	@echo "Building malware binaries..."
	cd malware && make

clean:
	@echo "Cleaning all binaries..."
	cd fake-bpfdoor && make clean
	cd malware && make clean 2>/dev/null || true

re: clean all

