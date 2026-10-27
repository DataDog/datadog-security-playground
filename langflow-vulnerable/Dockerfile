# Manually instrumented build of the CVE-2025-3248-vulnerable Langflow image,
# pinned by digest to the last version before the fix (1.2.0). The upstream
# image currently ships Python 3.12.3; ddtrace is pinned below to the released
# dd-trace-py 4.14.0 build and wrapped via ddtrace-run.
FROM langflowai/langflow@sha256:1e9cfdb0e1565b1187bdd3c6849493ecbd81627645214ab0537d7cbcdbdb454a

# GIT_SHA pins payload downloads from Github to the commit the image was built from
# so scenarios stay reproducible as main moves forward. Defaults to "main" for
# bare `docker build` invocations; Github CI Workflows pass the real SHA.
ARG GIT_SHA=main
ARG DDTRACE_VERSION=4.14.0
ENV GIT_SHA=${GIT_SHA}

# The upstream image runs as a non-root "user" (uid 1000) with no sudo/curl/jq/
# awscli, which breaks the rce-malware and cloud-access scenario scripts
# (assets/rce-malware/payload.sh, assets/cloud-access/cloud-access.sh) at
# runtime -- apt has no network egress or write perms from inside the exploited
# pod. Bake the same dependencies playground-app bakes (see app/Dockerfile) at
# build time instead, when root + network are actually available, and run the
# container as root so the scenario scripts work unmodified.
#
# curl:     download payloads and IMDS access in rce-malware and cloud-access
# jq:       parse IMDS JSON credentials in rce-malware/cloud-access
# awscli:   AWS API calls (ec2 run-instances) in cloud-access
# dnsutils: dig to mining pools in rce-malware/payload
# procps:   pkill for cleanup in rce-malware
USER root
RUN apt update && apt install -y \
    curl jq awscli dnsutils procps && \
    touch /etc/rc.common

# Install the released ddtrace build that publishes the OTel thread-local
# context CWS reads to correlate APM traces with security events. The upstream
# image's venv ships without pip (PATH resolves the system /usr/local/bin/pip
# instead, which would install into the wrong Python), so bootstrap pip into
# /app/.venv directly before installing ddtrace there.
RUN /app/.venv/bin/python3 -m ensurepip --default-pip && \
    /app/.venv/bin/python3 -m pip install --no-cache-dir --upgrade \
        "ddtrace==${DDTRACE_VERSION}" && \
    /app/.venv/bin/python3 -c \
        "import ddtrace; assert ddtrace.__version__ == '${DDTRACE_VERSION}', ddtrace.__version__"

# ddtrace-run wraps the process for manual instrumentation now that this pod
# opts out of SSI (see the admission-controller exclusion label in
# deploy/langflow-vulnerable.yaml) -- SSI would otherwise inject its own
# tracer via PYTHONPATH and clobber the image-pinned ddtrace release.
ENTRYPOINT ["/app/.venv/bin/ddtrace-run", "langflow", "run"]
