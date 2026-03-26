#!/usr/bin/env bash
# validate.sh — Pre-flight and smoke tests
# Usage:
#   ./scripts/validate.sh okta
#   ./scripts/validate.sh aws dev ec2
#   ./scripts/validate.sh aws staging ecs

set -euo pipefail

TARGET="${1:-}"
ENV="${2:-dev}"
COMPUTE="${3:-ec2}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✔ $1${NC}"; }
fail() { echo -e "${RED}✘ $1${NC}"; exit 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

# ── Okta smoke test ────────────────────────────────────────────────────────────
test_okta() {
  info "Running Okta smoke tests..."

  [[ -z "${OKTA_ORG_URL:-}" ]] && fail "OKTA_ORG_URL not set"
  [[ -z "${OKTA_API_TOKEN:-}" ]] && fail "OKTA_API_TOKEN not set"

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
    -H "Accept: application/json" \
    "${OKTA_ORG_URL}/api/v1/users?limit=1")

  [[ "$HTTP_STATUS" == "200" ]] || fail "Okta API returned HTTP $HTTP_STATUS"
  pass "Okta API reachable and token valid"

  USER_COUNT=$(curl -s \
    -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
    -H "Accept: application/json" \
    "${OKTA_ORG_URL}/api/v1/users?limit=200&filter=status+eq+%22ACTIVE%22" | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

  [[ "$USER_COUNT" -gt 0 ]] || fail "No active users found — Okta provisioning may have failed"
  pass "Active users found: $USER_COUNT"
}

# ── AWS EC2 smoke test ─────────────────────────────────────────────────────────
test_ec2() {
  info "Running EC2 smoke tests (env=$ENV)..."

  INSTANCE_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=${ENV}" "Name=instance-state-name,Values=running" \
    --query "length(Reservations[*].Instances[*])" \
    --output text)

  [[ "$INSTANCE_COUNT" -gt 0 ]] || fail "No running EC2 instances found with tag Environment=$ENV"
  pass "Running EC2 instances: $INSTANCE_COUNT"
}

# ── AWS ECS smoke test ─────────────────────────────────────────────────────────
test_ecs() {
  info "Running ECS smoke tests (env=$ENV)..."

  CLUSTER="${ENV}-cluster"
  RUNNING=$(aws ecs describe-clusters --clusters "$CLUSTER" \
    --query "clusters[0].runningTasksCount" --output text 2>/dev/null || echo "0")

  [[ "$RUNNING" != "None" && "$RUNNING" -gt 0 ]] || fail "No running ECS tasks in cluster $CLUSTER"
  pass "Running ECS tasks: $RUNNING"
}

# ── AWS EKS smoke test ─────────────────────────────────────────────────────────
test_eks() {
  info "Running EKS smoke tests (env=$ENV)..."

  CLUSTER="${ENV}-cluster"
  STATUS=$(aws eks describe-cluster --name "$CLUSTER" \
    --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")

  [[ "$STATUS" == "ACTIVE" ]] || fail "EKS cluster $CLUSTER status is $STATUS (expected ACTIVE)"
  pass "EKS cluster $CLUSTER is ACTIVE"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
case "$TARGET" in
  okta)
    test_okta
    ;;
  aws)
    case "$COMPUTE" in
      ec2)  test_ec2 ;;
      ecs)  test_ecs ;;
      eks)  test_eks ;;
      *)    fail "Unknown compute type: $COMPUTE. Use ec2, ecs, or eks." ;;
    esac
    ;;
  *)
    fail "Unknown target: $TARGET. Use 'okta' or 'aws'."
    ;;
esac

pass "All smoke tests passed for $TARGET${COMPUTE:+/$COMPUTE} ($ENV)"
