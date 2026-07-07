FROM python:3.12-slim

ARG ATOMIC_RED_TEAM=false
ARG PORT=5000

# GIT_SHA pins payload downloads from Github to the commit the image was built from
# so scenarios stay reproducible as main moves forward. Defaults to "main" for
# bare `docker build` invocations; Github CI Workflows pass the real SHA.
ARG GIT_SHA=main
ENV GIT_SHA=${GIT_SHA}

RUN \
    touch /etc/rc.common
COPY \
    scripts /scripts
COPY \
    scenarios /scenarios


# sudo:     privilege escalation in bpfdoor and findings-generator
# curl:     download payloads and IMDS access in rce-malware and bpfdoor
# jq:       parse IMDS JSON credentials in rce-malware/cloud-access
# awscli:   AWS API calls (ec2 run-instances) in rce-malware/cloud-access
# dnsutils: dig to mining pools in rce-malware/payload
# procps:   pkill for cleanup in rce-malware
RUN apt update && apt install -y \
    sudo curl jq awscli dnsutils procps
RUN \
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

#
# Atomic Red Team
#
RUN if [ "$ATOMIC_RED_TEAM" = "true" ]; then \
        apt-get update && \
        apt-get install -y wget lsb-release libgssapi-krb5-2 && \
        wget https://github.com/berkley4/icu-74-debian/releases/download/74.2-2/libicu74_74.2-2_amd64.deb && \
        dpkg --install ./libicu74_74.2-2_amd64.deb && \
        wget https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/powershell_7.5.3-1.deb_amd64.deb && \
        dpkg -i powershell_7.5.3-1.deb_amd64.deb && \
        rm libicu74_74.2-2_amd64.deb powershell_7.5.3-1.deb_amd64.deb && \
        apt install -y sudo make kmod gcc nmap clang iproute2 curl && \
        pwsh -Command "IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/v2.0.0.0/install-atomicredteam.ps1' -UseBasicParsing); Install-AtomicRedTeam -getAtomics" && \
        mkdir -p /root/.config/powershell && \
        echo 'Import-Module "/root/AtomicRedTeam/invoke-atomicredteam/Invoke-AtomicRedTeam.psd1" -Force' > /root/.config/powershell/profile.ps1; \
    fi

# Vulnerable application

# install vulnerable library
RUN \
    apt install -y python3-socketio=5.12.1-1

RUN \
    mkdir /app
RUN \
    groupadd --gid 1000 app
RUN \
    useradd --home-dir /app --create-home --uid 1000 --gid 1000 --shell /bin/bash app

WORKDIR /app

COPY app/app.py /app/app.py
COPY app/templates /app/templates
COPY app/requirements.txt /app/requirements.txt
RUN \
    pip install --no-cache-dir -r /app/requirements.txt

# Custom dd-trace-py build (DataDog/dd-trace-py#18872) that publishes the OTel
# thread-local context CWS reads to correlate APM traces with security events
# (datadog-agent#48446). This page is a flat links page, not a PEP 503 index
# root, so it must be passed via --find-links, not --index-url/
# --extra-index-url (which appends "/<pkg>/" to the URL and 404s, silently
# falling back to PyPI). Also pinned to the exact build version — pip
# excludes pre-releases like this "rc1" build by default.
RUN \
    pip install --no-cache-dir \
        --find-links https://dd-trace-py-builds.s3.amazonaws.com/3581ca6284299ab47a20c534f50ac833df60c0ea/index-manylinux2014_x86_64.html \
        "ddtrace==4.12.0rc1+g3581ca6"
RUN \
    chown -R app:app /app

# --threads 4 enables the gthread worker so nested /inject calls from detonate scripts
# (which curl back into /inject for each attack step) don't deadlock on a single sync worker.
# --timeout 600 because the sync timeout would otherwise kill long-running scenario steps.
# ddtrace-run wraps the process for manual instrumentation now that this pod
# opts out of SSI (see admission-controller exclusion label) — SSI would
# otherwise inject its own tracer and clobber the custom dd-trace-py wheel.
ENTRYPOINT ["ddtrace-run", "gunicorn", "-b", ":5000", "--timeout", "600", "--threads", "4", "app:app"]
EXPOSE $PORT