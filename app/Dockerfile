FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir flask boto3

# Copy application files
COPY app/html/* /var/www/html/
RUN chmod +x /var/www/html/app.py && \
    touch /etc/rc.common

# Copy scripts
COPY scripts /scripts

WORKDIR /var/www/html


# Expose port 80
EXPOSE 80

# Run the Flask app
CMD ["python3", "/var/www/html/app.py"]
