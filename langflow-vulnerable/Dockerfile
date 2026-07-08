# Custom-instrumented build of the CVE-2025-3248-vulnerable Langflow image,
# pinned by digest to the last version before the fix (1.2.0). Mirrors the
# instrumentation approach used for playground-app (see app/Dockerfile): a
# custom dd-trace-py build wrapped via ddtrace-run, instead of relying on
# Datadog Single-Step Instrumentation.
FROM langflowai/langflow@sha256:1e9cfdb0e1565b1187bdd3c6849493ecbd81627645214ab0537d7cbcdbdb454a

# Custom dd-trace-py build (DataDog/dd-trace-py#18872) that publishes the OTel
# thread-local context CWS reads to correlate APM traces with security events
# (datadog-agent#48446) -- same build used for playground-app. The upstream
# image's venv ships without pip (PATH resolves the system /usr/local/bin/pip
# instead, which would install into the wrong Python), so bootstrap pip into
# /app/.venv directly before installing the wheel there.
RUN /app/.venv/bin/python3 -m ensurepip --default-pip && \
    /app/.venv/bin/python3 -m pip install --no-cache-dir \
        --find-links https://dd-trace-py-builds.s3.amazonaws.com/97c1f5ce4336a82030f01056ede78c9c13c992f7/index.html \
        "ddtrace==4.12.0rc1+g97c1f5c"

# ddtrace-run wraps the process for manual instrumentation now that this pod
# opts out of SSI (see the admission-controller exclusion label in
# deploy/langflow-vulnerable.yaml) -- SSI would otherwise inject its own
# tracer via PYTHONPATH and clobber the custom wheel.
ENTRYPOINT ["ddtrace-run", "langflow", "run"]
