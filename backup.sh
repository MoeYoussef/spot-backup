#!/bin/bash
# OpenClaw Agent Backup Script
# Backs up Spot, Bubble, and Realtor agent data
# Pushes to GitHub repos after backup

BACKUP_DIR="/opt/openclaw-backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG="$BACKUP_DIR/logs/backup.log"
RETENTION_DAYS=30
GIT_SSH="ssh -i /root/.ssh/github_spot -o StrictHostKeyChecking=accept-new"

SPOT_CONTAINER="13b3665ed192"
BUBBLE_CONTAINER="c0847b2cbefb"
REALTOR_CONTAINER="44fda691d268"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

backup_container() {
    local name=$1
    local container_id=$2
    local dest="$BACKUP_DIR/$name"
    mkdir -p "$dest"

    local file="$dest/${TIMESTAMP}.tar.gz"
    log "Backing up $name ($container_id)..."

    docker exec "$container_id" tar czf - /data/.openclaw /root 2>/dev/null > "$file"
    local exit_code=$?

    if [ $exit_code -ne 0 ] && [ ! -s "$file" ]; then
        log "ERROR: $name backup failed (docker exec exit=$exit_code, empty file)"
        rm -f "$file"
        return 1
    fi

    local size
    size=$(du -sh "$file" | cut -f1)
    log "$name backup: $file ($size)"

    find "$dest" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null
    local count=$(ls -1 "$dest"/*.tar.gz 2>/dev/null | wc -l)
    log "$name: $count backups retained"

    return 0
}

push_to_github() {
    local name=$1
    local repo=$2
    local repo_dir="$BACKUP_DIR/${name}-repo"

    if [ ! -d "$repo_dir/.git" ]; then
        log "Cloning $repo..."
        GIT_SSH_COMMAND="$GIT_SSH" git clone "git@github.com:MoeYoussef/${repo}.git" "$repo_dir" 2>&1 | tee -a "$LOG"
    fi

    cd "$repo_dir"
    git config user.email "support@softwareque.com"
    git config user.name "Spot"

    # Copy latest backup scripts
    cp "$BACKUP_DIR/backup.sh" ./backup.sh
    cp "$BACKUP_DIR/check_claude_cli.sh" ./check_claude_cli.sh 2>/dev/null

    # Copy latest config from container
    local container_id=$3
    docker exec "$container_id" cat /data/.openclaw/openclaw.json > ./openclaw.json 2>/dev/null

    # Update status
    cat > STATUS.md << STATUS
# $name Backup Status

Last backup: $TIMESTAMP
Container: $container_id
STATUS

    git add -A
    if git diff --cached --quiet; then
        log "$name repo: no changes to push"
    else
        git commit -m "Backup $TIMESTAMP" 2>&1 | tee -a "$LOG"
        GIT_SSH_COMMAND="$GIT_SSH" git push 2>&1 | tee -a "$LOG"
        log "$name repo: pushed to GitHub"
    fi
}

mkdir -p "$BACKUP_DIR/logs" "$BACKUP_DIR/spot" "$BACKUP_DIR/bubble" "$BACKUP_DIR/realtor"

log "=== OpenClaw Backup started (PID $$) ==="

AVAIL_KB=$(df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
log "Available disk space: ${AVAIL_GB}GB"
if [ "$AVAIL_GB" -lt 5 ]; then
    log "WARNING: Low disk space (${AVAIL_GB}GB)."
fi

backup_container "spot" "$SPOT_CONTAINER"
SPOT_STATUS=$?

backup_container "bubble" "$BUBBLE_CONTAINER"
BUBBLE_STATUS=$?

backup_container "realtor" "$REALTOR_CONTAINER"
REALTOR_STATUS=$?

# Push configs to GitHub repos
log "Pushing to GitHub..."
push_to_github "spot" "spot-backup" "$SPOT_CONTAINER"
push_to_github "bubble" "bubble-backup" "$BUBBLE_CONTAINER"
push_to_github "realtor" "realtor-backup" "$REALTOR_CONTAINER"

if [ $SPOT_STATUS -eq 0 ] && [ $BUBBLE_STATUS -eq 0 ] && [ $REALTOR_STATUS -eq 0 ]; then
    log "=== Backup complete — ALL HEALTHY ==="
else
    log "=== Backup complete — FAILURES (spot=$SPOT_STATUS bubble=$BUBBLE_STATUS realtor=$REALTOR_STATUS) ==="
    exit 1
fi