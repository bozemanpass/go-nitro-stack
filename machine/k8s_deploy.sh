#!/bin/bash

STACK_NAME="din-caddy"
STACK_DIN_REPO="bozemanpass/${STACK_NAME}-stack"
STACK_FXETH_REPO="bozemanpass/fixturenet-eth-stack"
STACK_FXETH_NAME="fixturenet-eth"
STACK_HTTP_TARGET="din-caddy:8000"

BPI_SCRIPT_DEBUG="${BPI_SCRIPT_DEBUG}"

IMAGE_REGISTRY=""
IMAGE_REGISTRY_USERNAME=""
IMAGE_REGISTRY_PASSWORD=""
HTTP_PROXY_FQDN="${MACHINE_FQDN}"
HTTP_PROXY_CLUSTER_ISSUER=""
HTTP_PROXY_TARGET_SVC="$STACK_HTTP_TARGET"
BUILD_POLICY="as-needed"

while (( "$#" )); do
   case $1 in
      --build-policy)
         BUILD_POLICY="$1"||die
         ;;
      --debug)
         BPI_SCRIPT_DEBUG="true"
         ;;
      --image-registry)
         shift&&IMAGE_REGISTRY="$1"||die
         ;;
      --image-registry-username)
         shift&&IMAGE_REGISTRY_USERNAME="$1"||die
         ;;
      --image-registry-password)
         shift&&IMAGE_REGISTRY_PASSWORD="$1"||die
         ;;
      --http-proxy-target)
         shift&&HTTP_PROXY_TARGET_SVC="$1"||die
         ;;
      --http-proxy-fqdn)
         shift&&HTTP_PROXY_FQDN="$1"||die
         ;;
      --http-proxy-cluster-issuer)
         shift&&HTTP_PROXY_CLUSTER_ISSUER="$1"||die
         ;;
         *)
         echo "Unrecognized argument: $1" 1>&2
         ;;
   esac
   shift
done

STACK_CMD="stack"
if [[ -n "${BPI_SCRIPT_DEBUG}" ]]; then
  set -x
  STACK_CMD="${STACK_CMD} --debug --verbose"
fi

set -Eeo pipefail

if [[ -z "$IMAGE_REGISTRY" ]]; then
  if [[ -f "/etc/rancher/k3s/default-registry.yaml" ]]; then
    IMAGE_REGISTRY=$(cat /etc/rancher/k3s/default-registry.yaml | grep 'default:' | head -1 | awk '{ print $2 }' | sed "s/[\"']//g")
  elif [[ -f "/etc/rancher/k3s/registries.yaml" ]]; then
    IMAGE_REGISTRY=$(cat /etc/rancher/k3s/registries.yaml | grep -A1 'configs:$' | tail -1 | awk '{ print $1 }' | cut -d':' -f1)
  fi
fi

IMAGE_REGISTRY=$(echo $IMAGE_REGISTRY | sed 's|https\?://||')

if [[ -z "$IMAGE_REGISTRY_USERNAME" ]]; then
  # TODO: Match to specific registry.
  if [[ -f "/etc/rancher/k3s/registries.yaml" ]]; then
    IMAGE_REGISTRY_USERNAME=$(cat /etc/rancher/k3s/registries.yaml | grep 'username:' | head -1 | awk '{ print $2 }' | sed "s/[\"']//g")
    IMAGE_REGISTRY_PASSWORD=$(cat /etc/rancher/k3s/registries.yaml | grep 'password:' | head -1 |awk '{ print $2 }' | sed "s/[\"']//g")
  fi
fi

docker login --username "$IMAGE_REGISTRY_USERNAME" --password "$IMAGE_REGISTRY_PASSWORD" $IMAGE_REGISTRY

$STACK_CMD fetch-stack $STACK_DIN_REPO
$STACK_CMD fetch-stack $STACK_FXETH_REPO

$STACK_CMD --stack ~/bpi/$(basename $STACK_DIN_REPO)/stacks/$STACK_NAME setup-repositories
$STACK_CMD --stack ~/bpi/$(basename $STACK_DIN_REPO)/stacks/$STACK_NAME prepare-containers --image-registry $IMAGE_REGISTRY --build-policy $BUILD_POLICY --publish-images

$STACK_CMD --stack ~/bpi/$(basename $STACK_FXETH_REPO)/stacks/$STACK_FXETH_NAME setup-repositories
$STACK_CMD --stack ~/bpi/$(basename $STACK_FXETH_REPO)/stacks/$STACK_FXETH_NAME prepare-containers --image-registry $IMAGE_REGISTRY --build-policy $BUILD_POLICY --publish-images

sudo chmod a+r /etc/rancher/k3s/k3s.yaml

HTTP_PROXY_ARG=""
if [[ -n "${HTTP_PROXY_FQDN}" ]] && [[ -n "${HTTP_PROXY_TARGET_SVC}" ]]; then
  if [[ -n "${HTTP_PROXY_CLUSTER_ISSUER}" ]]; then
    HTTP_PROXY_ARG="--http-proxy ${HTTP_PROXY_CLUSTER_ISSUER}~${HTTP_PROXY_FQDN}:${HTTP_PROXY_TARGET_SVC}"
  else
    HTTP_PROXY_ARG="--http-proxy ${HTTP_PROXY_FQDN}:${HTTP_PROXY_TARGET_SVC}"
  fi
else
  echo "No FQDN or target service set for HTTP proxy; skipping proxy setup."
fi

$STACK_CMD \
  --stack ~/bpi/$(basename $STACK_DIN_REPO)/stacks/$STACK_NAME \
  deploy \
    --deploy-to k8s \
    init \
      --output din.yml \
      --kube-config /etc/rancher/k3s/k3s.yaml \
      --image-registry $IMAGE_REGISTRY ${HTTP_PROXY_ARG}

$STACK_CMD \
  --stack ~/bpi/$(basename $STACK_FXETH_REPO)/stacks/$STACK_FXETH_NAME \
  deploy \
    --deploy-to k8s \
    init \
      --output fxeth.yml \
      --kube-config /etc/rancher/k3s/k3s.yaml \
      --image-registry $IMAGE_REGISTRY

mkdir $HOME/deployments

$STACK_CMD \
  deploy \
    create \
     --spec-file din.yml \
     --spec-file fxeth.yml \
     --deployment-dir $HOME/deployments/$STACK_NAME

$STACK_CMD deployment --dir $HOME/deployments/$STACK_NAME push-images
$STACK_CMD deployment --dir $HOME/deployments/$STACK_NAME start
