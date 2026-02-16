FROM nginx:1.29.5-alpine

RUN apk add --no-cache curl

RUN case "$(uname -m)" in \
    x86_64|amd64) echo "amd64" > /tmp/module_arch ;; \
    aarch64|arm64) echo "arm64" > /tmp/module_arch ;; \
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac

RUN curl -fL --retry 3 --retry-all-errors \
    "https://github.com/DataDog/nginx-datadog/releases/download/v1.12.0/ngx_http_datadog_module-$(cat /tmp/module_arch)-1.29.5.so.tgz" \
    -o /tmp/ngx_http_datadog_module.so.tgz

RUN mkdir -p /opt/datadog/nginx/modules \
    && tar -xzf /tmp/ngx_http_datadog_module.so.tgz -C /opt/datadog/nginx/modules

COPY nginx.conf /etc/nginx/nginx.conf
