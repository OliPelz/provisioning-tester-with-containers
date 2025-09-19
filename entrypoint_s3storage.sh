#!/bin/sh
set -e

# Start MinIO in the background and bind to all interfaces
minio server --address ":9000" /data &

# Wait for MinIO to be ready
echo "Waiting for MinIO to start..."
sleep 5

export SSL_CERT_FILE=/root/.minio/certs/public.crt

# Configure mc alias pointing to container hostname (network accessible)
mc alias set local https://s3storage:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD --api s3v4 --path on

# Create test bucket
mc mb local/harbormockbucket || true

mc mb local/harbormockbucket/s3/imreg/harbor_stage || true

# Keep MinIO running in foreground
wait
