FROM python:3.12-slim

ARG ATOMIC_RED_TEAM=true
ARG PORT=5000

RUN \
    touch /etc/rc.common
COPY \
    scripts /scripts
COPY \
    scenarios /scenarios


# needed for bpfdoor
RUN \
    apt update && apt install -y sudo curl jq awscli dnsutils
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
RUN \
    chown -R app:app /app

ENTRYPOINT ["ddtrace-run", "python", "/app/app.py" ]
EXPOSE $PORT