#!/usr/bin/env bash
# Source before running the IBM Cloud commands in README.md:
#   source env.sh

export IBM_REGION=""
export RESOURCE_GROUP=""

export VPC_NAME=""
export SUBNET_NAME=""

export VPN_GATEWAY_NAME=""
export VPN_CONNECTION_NAME=""
export IKE_POLICY_NAME=""
export IPSEC_POLICY_NAME=""

# Generate with: openssl rand -hex 32   (alphanumeric-only; IBM rejects
# some special characters in the PSK)
export PSK=""

# Fill these in once the peer VM exists (see README Part 2)
export PEER_PUBLIC_IP=""   # the VM's real, non-NAT'd public IP
export PEER_PRIVATE_IP=""  # the VM's private/internal IP - used as its IKE identity

# IBM Cloud's reserved Cloud Service Endpoints range - do not change
export CSE_RANGE=""