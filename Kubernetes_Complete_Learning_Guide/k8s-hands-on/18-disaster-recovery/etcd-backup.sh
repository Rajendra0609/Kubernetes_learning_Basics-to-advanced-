#!/usr/bin/env bash
# ============================================================
# etcd Backup Script
# ============================================================
# Run on the control-plane node. Creates a snapshot of etcd
# and uploads to S3. Schedule via cron: 0 */6 * * * /opt/etcd-backup.sh
# ============================================================
set -euo pipefail

BACKUP_DIR="/opt/etcd-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="$BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"
S3_BUCKET="s3://my-etcd-backups"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "[$TIMESTAMP] Starting etcd snapshot..."

ETCDCTL_API=3 etcdctl snapshot save "$SNAPSHOT_FILE" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify snapshot
ETCDCTL_API=3 etcdctl snapshot status "$SNAPSHOT_FILE" --write-out=table

# Compress
gzip "$SNAPSHOT_FILE"
echo "Snapshot saved: ${SNAPSHOT_FILE}.gz"

# Upload to S3
if command -v aws &>/dev/null; then
  aws s3 cp "${SNAPSHOT_FILE}.gz" "$S3_BUCKET/$(basename ${SNAPSHOT_FILE}.gz)"
  echo "Uploaded to S3: $S3_BUCKET"
fi

# Cleanup old local backups
find "$BACKUP_DIR" -name "etcd-snapshot-*.db.gz" -mtime "+$RETENTION_DAYS" -delete
echo "Cleaned up backups older than $RETENTION_DAYS days"

echo "[$TIMESTAMP] etcd backup complete."

# ── Restore procedure (DO NOT run during normal operation) ────
# 1. Stop kube-apiserver:  mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
# 2. Restore snapshot:
#    ETCDCTL_API=3 etcdctl snapshot restore /path/to/snapshot.db \
#      --data-dir /var/lib/etcd-restored \
#      --initial-cluster "master=https://127.0.0.1:2380" \
#      --initial-advertise-peer-urls https://127.0.0.1:2380 \
#      --name master
# 3. Update etcd manifest to use new data dir
# 4. Restart: mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
