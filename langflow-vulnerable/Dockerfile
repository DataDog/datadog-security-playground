# Custom-instrumented build of the CVE-2025-3248-vulnerable Langflow image,
# pinned by digest to the last version before the fix (1.2.0). Mirrors the
# instrumentation approach used for playground-app (see app/Dockerfile): a
# custom dd-trace-py build wrapped via ddtrace-run, instead of relying on
# Datadog Single-Step Instrumentation.
FROM langflowai/langflow@sha256:1e9cfdb0e1565b1187bdd3c6849493ecbd81627645214ab0537d7cbcdbdb454a

# GIT_SHA pins payload downloads from Github to the commit the image was built from
# so scenarios stay reproducible as main moves forward. Defaults to "main" for
# bare `docker build` invocations; Github CI Workflows pass the real SHA.
ARG GIT_SHA=main
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

# Custom dd-trace-py build (DataDog/dd-trace-py#18872, branch
# florentin.labelle/thread-context-sharing) that publishes the OTel
# thread-local context CWS reads to correlate APM traces with security events
# (datadog-agent#48446). Newer build than the one currently baked into
# playground-app (app/Dockerfile still pins the 97c1f5c build). The upstream
# image's venv ships without pip (PATH resolves the system /usr/local/bin/pip
# instead, which would install into the wrong Python), so bootstrap pip into
# /app/.venv directly before installing the wheel there.
RUN /app/.venv/bin/python3 -m ensurepip --default-pip && \
    /app/.venv/bin/python3 -m pip install --no-cache-dir \
        --find-links https://dd-trace-py-builds.s3.amazonaws.com/81bc1deb8cb43703e82a42c72a9387f037c0a8db/index.html \
        "ddtrace==4.12.0rc1"

# ddtrace-run wraps the process for manual instrumentation now that this pod
# opts out of SSI (see the admission-controller exclusion label in
# deploy/langflow-vulnerable.yaml) -- SSI would otherwise inject its own
# tracer via PYTHONPATH and clobber the custom wheel.
ENTRYPOINT ["ddtrace-run", "langflow", "run"]
