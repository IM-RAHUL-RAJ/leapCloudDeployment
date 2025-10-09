#!/usr/bin/env bash

# install-aws-load-balancer-controller.sh
# Purpose: Idempotent installer for AWS Load Balancer Controller (ALB Ingress Controller)
# Usage: ./scripts/install-aws-load-balancer-controller.sh -c <cluster-name> -r <region> [-v <vpc-id>] [-p <policy-name>] [-n <namespace>] \
#        [--no-subnet-check] [--force-reinstall] [--extra-arg key=value] [--auto-tag-public-subnets] \
#        [--subnet-ids subnet-1,subnet-2] [--annotate-ingress <ingress-name>] [--ingress-namespace <ns>]
# Requires: aws, kubectl, helm, jq (eksctl optional for automated OIDC + IRSA)
# Features:
#  * Infers cluster name, region, VPC ID if omitted (from current kube context / EKS API)
#  * Ensures OIDC provider, IAM policy, and IRSA service account
#  * Optional subnet tag validation (on by default) for kubernetes.io/cluster/<cluster>
#  * Extended rollout timeout with rich diagnostics on failure (describe + recent logs)
#  * Passes vpcId to helm chart if available (addresses some reconciliation delays)

set -euo pipefail

trap 'on_err $LINENO' ERR

on_err() {
  echo "[ERROR] Script failed at line $1" >&2
  echo "[DIAG] Gathering controller diagnostics..." >&2
  kubectl get deployment aws-load-balancer-controller -n "${NAMESPACE:-kube-system}" 2>/dev/null || true
  kubectl get pods -n "${NAMESPACE:-kube-system}" -l app.kubernetes.io/name=aws-load-balancer-controller -o wide 2>/dev/null || true
  POD=$(kubectl get pods -n "${NAMESPACE:-kube-system}" -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$POD" ]]; then
    echo "[DIAG] Describe pod:" >&2
    kubectl describe pod "$POD" -n "${NAMESPACE:-kube-system}" 2>/dev/null | sed 's/^/    /' || true
    echo "[DIAG] Last 80 log lines:" >&2
    kubectl logs "$POD" -n "${NAMESPACE:-kube-system}" 2>/dev/null | tail -n 80 | sed 's/^/    /' || true
  fi
  echo "[HINT] Check: SA IAM annotation, IAM permissions, subnet tags, security group rules, and chart/controller versions." >&2
}

DEFAULT_NAMESPACE="kube-system"
POLICY_NAME_DEFAULT="AWSLoadBalancerControllerIAMPolicy"
CHART_VERSION="1.7.2"          # Helm chart version (maps to controller v2.7.2)
CONTROLLER_VERSION="v2.7.2"    # Keep IAM policy revision aligned
REPO_NAME="eks"
REPO_URL="https://aws.github.io/eks-charts"
SERVICE_ACCOUNT="aws-load-balancer-controller"

CLUSTER_NAME=""
REGION=""
VPC_ID=""
POLICY_NAME="$POLICY_NAME_DEFAULT"
NAMESPACE="$DEFAULT_NAMESPACE"
SUBNET_CHECK=1
FORCE_REINSTALL=0
EXTRA_ARGS=()
AUTO_TAG_PUBLIC=0
EXPLICIT_SUBNET_IDS=""
ANNOTATE_INGRESS=""
INGRESS_NAMESPACE="default"

usage() {
  grep '^#' "$0" | sed 's/^# //'
  exit 1
}

require_value() {
  local opt="$1" val="$2"
  if [[ -z "$val" || "$val" =~ ^- ]]; then
    echo "[ERROR] Option $opt requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c) require_value -c "${2:-}"; CLUSTER_NAME="$2"; shift 2 ;;
    -r) require_value -r "${2:-}"; REGION="$2"; shift 2 ;;
    -v) require_value -v "${2:-}"; VPC_ID="$2"; shift 2 ;;
    -p) require_value -p "${2:-}"; POLICY_NAME="$2"; shift 2 ;;
    -n) require_value -n "${2:-}"; NAMESPACE="$2"; shift 2 ;;
  --no-subnet-check) SUBNET_CHECK=0; shift ;;
    --force-reinstall) FORCE_REINSTALL=1; shift ;;
    --extra-arg)
        if [[ -z "${2:-}" || "$2" != *=* ]]; then
          echo "[ERROR] --extra-arg requires key=value argument" >&2; exit 1
        fi
        EXTRA_ARGS+=("$2"); shift 2 ;;
    --extra-arg=*)
        EXTRA_ARGS+=("${1#*=}"); shift ;;
  --auto-tag-public-subnets) AUTO_TAG_PUBLIC=1; shift ;;
  --subnet-ids)
    require_value --subnet-ids "${2:-}"; EXPLICIT_SUBNET_IDS="$2"; shift 2 ;;
  --annotate-ingress)
    require_value --annotate-ingress "${2:-}"; ANNOTATE_INGRESS="$2"; shift 2 ;;
  --ingress-namespace)
    require_value --ingress-namespace "${2:-}"; INGRESS_NAMESPACE="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "[ERROR] Unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
done

if [[ -z "${CLUSTER_NAME}" ]]; then
  # Try to infer from current context (EKS contexts usually: arn:aws:eks:<region>:<acct>:cluster/<name>)
  CURRENT_CTX=$(kubectl config current-context 2>/dev/null || true)
  CLUSTER_NAME=${CURRENT_CTX##*/}
  echo "[INFO] Inferred cluster name: $CLUSTER_NAME" >&2
fi

if [[ -z "${REGION}" ]]; then
  # Try to parse from current context ARN style
  CURRENT_CTX=$(kubectl config current-context 2>/dev/null || true)
  REGION=$(echo "$CURRENT_CTX" | awk -F: '/eks/{print $4}' || true)
  [[ -z "$REGION" ]] && { echo "[ERROR] Region not supplied (-r) and could not infer." >&2; exit 1; }
  echo "[INFO] Inferred region: $REGION" >&2
fi

command -v aws >/dev/null || { echo "[ERROR] aws CLI not found" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "[ERROR] kubectl not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "[ERROR] jq not found" >&2; exit 1; }

# Install Helm if not present
if ! command -v helm >/dev/null; then
  echo "[INFO] Helm not found, installing Helm v3.15.0..."
  HELM_VERSION="v3.15.0"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -zxf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
  sudo mv linux-amd64/helm /usr/local/bin/helm
  cd - >/dev/null
  rm -rf "$TMPDIR"
  echo "[INFO] Helm installed: $(helm version --short)"
else
  echo "[INFO] Using existing Helm: $(helm version --short)"
fi

echo "[INFO] Validating cluster access..."
kubectl get nodes >/dev/null

echo "[INFO] Ensuring OIDC provider for cluster..."
OIDC_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.identity.oidc.issuer' --output text)
OIDC_HOST=${OIDC_URL#*//}
if aws iam list-open-id-connect-providers | grep -q "$OIDC_HOST"; then
  echo "[INFO] OIDC provider already exists." 
else
  if command -v eksctl >/dev/null; then
    echo "[INFO] Creating OIDC provider via eksctl" 
    eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --region "$REGION" --approve
  else
    echo "[ERROR] OIDC provider missing and eksctl not installed. Install eksctl or create provider manually." >&2
    exit 1
  fi
fi

echo "[INFO] Ensuring IAM policy $POLICY_NAME exists..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/$POLICY_NAME"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "[INFO] Creating IAM policy $POLICY_NAME (controller $CONTROLLER_VERSION)"
  TMPF=$(mktemp)
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${CONTROLLER_VERSION}/docs/install/iam_policy.json" -o "$TMPF"
  aws iam create-policy --policy-name "$POLICY_NAME" --policy-document file://"$TMPF" >/dev/null
else
  echo "[INFO] IAM policy already exists." 
fi

echo "[INFO] Creating/ensuring service account with IAM role..."
if command -v eksctl >/dev/null; then
  eksctl create iamserviceaccount \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --namespace "$NAMESPACE" \
    --name "$SERVICE_ACCOUNT" \
    --attach-policy-arn "$POLICY_ARN" \
    --approve \
    --override-existing-serviceaccounts >/dev/null || true
else
  echo "[WARN] eksctl not found; ensure SA + role annotated manually." >&2
fi

echo "[INFO] Verifying service account IAM annotation..."
SA_JSON=$(kubectl get sa "$SERVICE_ACCOUNT" -n "$NAMESPACE" -o json 2>/dev/null || true)
if echo "$SA_JSON" | jq -e '.metadata.annotations["eks.amazonaws.com/role-arn"]' >/dev/null 2>&1; then
  echo "[INFO] Service account has IAM role annotation." 
else
  echo "[WARN] Service account missing eks.amazonaws.com/role-arn annotation." >&2
fi

if [[ -z "$VPC_ID" ]]; then
  VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)
  [[ -n "$VPC_ID" ]] && echo "[INFO] Inferred VPC ID: $VPC_ID"
fi

if [[ "$SUBNET_CHECK" -eq 1 ]]; then
  echo "[INFO] Validating subnet tags (kubernetes.io/cluster/$CLUSTER_NAME)..."
  SUBNET_IDS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.subnetIds' --output text 2>/dev/null || true)
  if [[ -n "$SUBNET_IDS" ]]; then
    MISSING=0
    for S in $SUBNET_IDS; do
      TAG_KEYS=$(aws ec2 describe-subnets --subnet-ids "$S" --region "$REGION" --query 'Subnets[0].Tags[].Key' --output text 2>/dev/null || true)
      if ! echo "$TAG_KEYS" | grep -q "kubernetes.io/cluster/${CLUSTER_NAME}"; then
        echo "[WARN] Subnet $S missing kubernetes.io/cluster/${CLUSTER_NAME} tag." >&2
        MISSING=1
      fi
    done
    [[ $MISSING -eq 1 ]] && echo "[WARN] Untagged subnets may prevent ALB creation." >&2
  else
    echo "[WARN] Could not list subnets for cluster to validate tags." >&2
  fi
else
  echo "[INFO] Skipping subnet tag validation (user disabled)."
fi

# --- Optional subnet tagging / selection ---
if [[ $AUTO_TAG_PUBLIC -eq 1 ]]; then
  echo "[INFO] Auto-tagging public subnets in VPC $VPC_ID (kubernetes.io/role/elb=1)";
  PUB_SUBNETS=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text 2>/dev/null || true)
  if [[ -z "$PUB_SUBNETS" ]]; then
    echo "[WARN] No public subnets discovered for auto-tagging." >&2
  else
    for S in $PUB_SUBNETS; do
      echo "[INFO] Tagging subnet $S for cluster + elb role"
      aws ec2 create-tags --region "$REGION" --resources "$S" --tags \
        Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared \
        Key=kubernetes.io/role/elb,Value=1 >/dev/null || true
    done
  fi
fi

ANNOTATION_SUBNET_LIST=""
if [[ -n "$EXPLICIT_SUBNET_IDS" ]]; then
  # Normalize commas (remove spaces)
  ANNOTATION_SUBNET_LIST=$(echo "$EXPLICIT_SUBNET_IDS" | tr -d ' ')
  echo "[INFO] Will annotate ingress with explicit subnets: $ANNOTATION_SUBNET_LIST"
  # Also ensure required tags are present for each explicit subnet
  IFS=',' read -r -a __EX_SPLIT <<< "$ANNOTATION_SUBNET_LIST"
  for S in "${__EX_SPLIT[@]}"; do
    [[ -z "$S" ]] && continue
    echo "[INFO] Tagging explicit subnet $S (cluster + kubernetes.io/role/elb=1)"
    aws ec2 create-tags --region "$REGION" --resources "$S" --tags \
      Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared \
      Key=kubernetes.io/role/elb,Value=1 >/dev/null 2>&1 || echo "[WARN] Failed tagging subnet $S" >&2
  done
fi

echo "[INFO] Adding Helm repo $REPO_NAME if needed..."
if ! helm repo list | grep -q "\b$REPO_NAME\b"; then
  helm repo add "$REPO_NAME" "$REPO_URL"
fi
helm repo update >/dev/null

if [[ $FORCE_REINSTALL -eq 1 ]]; then
  echo "[INFO] --force-reinstall specified: uninstalling any existing release first"
  helm uninstall aws-load-balancer-controller -n "$NAMESPACE" >/dev/null 2>&1 || true
  # Wait for old pods to terminate
  kubectl delete deployment aws-load-balancer-controller -n "$NAMESPACE" --ignore-not-found
  sleep 5
fi

echo "[INFO] Installing / upgrading AWS Load Balancer Controller chart..."
HELM_ARGS=(upgrade -i aws-load-balancer-controller $REPO_NAME/aws-load-balancer-controller
  -n "$NAMESPACE"
  --set clusterName="$CLUSTER_NAME"
  --set region="$REGION"
  --set serviceAccount.create=false
  --set serviceAccount.name="$SERVICE_ACCOUNT"
  --version "$CHART_VERSION")

if [[ -n "$VPC_ID" ]]; then
  echo "[INFO] Passing vpcId=$VPC_ID to chart"
  HELM_ARGS+=(--set vpcId="$VPC_ID")
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  for pair in "${EXTRA_ARGS[@]}"; do
    # Convert key=value to --set extraArgs.key=value (dots in key unsupported here)
    KEY=${pair%%=*}
    VAL=${pair#*=}
    echo "[INFO] Adding extra controller arg: $KEY=$VAL"
    HELM_ARGS+=(--set "extraArgs.$KEY=$VAL")
  done
fi

helm "${HELM_ARGS[@]}"

echo "[INFO] Waiting for deployment rollout (timeout 5m)..."
kubectl rollout status deployment/aws-load-balancer-controller -n "$NAMESPACE" --timeout=300s

echo "[INFO] Deployment ready. Controller args:"
kubectl get deployment aws-load-balancer-controller -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}'
echo

POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$POD" ]]; then
  echo "[INFO] Recent controller log lines (tail 25):"
  kubectl logs "$POD" -n "$NAMESPACE" --tail=25 2>/dev/null || true
fi

if [[ -n "$ANNOTATE_INGRESS" && -n "$ANNOTATION_SUBNET_LIST" ]]; then
  echo "[INFO] Annotating ingress $ANNOTATE_INGRESS in namespace $INGRESS_NAMESPACE with subnet list"
  kubectl annotate ingress "$ANNOTATE_INGRESS" -n "$INGRESS_NAMESPACE" \
    alb.ingress.kubernetes.io/subnets="$ANNOTATION_SUBNET_LIST" --overwrite || echo "[WARN] Failed to annotate ingress (ensure it exists)." >&2
fi

echo "[INFO] Installed successfully. Validate with: kubectl get ingressclasses; kubectl get ingress"
echo "[INFO] To uninstall: helm uninstall aws-load-balancer-controller -n $NAMESPACE (SA/IAM policy remain)"
