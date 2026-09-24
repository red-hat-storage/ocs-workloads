FROM python:3.11-alpine

# Create working directory
WORKDIR /app

# Install system tools
RUN apk add --no-cache curl

# Install Python dependency (faker)
RUN pip install --no-cache-dir faker

# Copy your uploader script
COPY data_writer_filebrowser.py /app/filebrowser_curl_client_rpo_rto_tagged.py

# Create a non-root user for OpenShift
RUN addgroup -g 1001 fbclient && adduser -D -u 1001 -G fbclient fbclient
USER 1001

# Environment setup
ENV PYTHONUNBUFFERED=1 \
    CONFIG_PATH=/config \
    TZ=UTC

# Optional: Healthcheck (comment out if using external probes)
# HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
#   CMD curl -fs http://filebrowser.filebrowser.svc.cluster.local:80/api/ || exit 1

# Default startup command
CMD ["python", "-u", "/app/filebrowser_curl_client_rpo_rto_tagged.py"]
