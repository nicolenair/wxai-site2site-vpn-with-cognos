#!/usr/bin/env bash
# Source before running provision.sh:
#   source env.sh

export AWS_REGION=""
export AWS_PROFILE="default"           # aws cli profile to use

# --- Instance sizing (Cognos min: 4+ cores, 32GB+ RAM) ---
export INSTANCE_TYPE="m8i.2xlarge"      # 8 vCPU, 32GB RAM
export WINDOWS_AMI_NAME="Windows_Server-2022-English-Full-Base-*"
export KEY_PAIR_NAME="cognos-vm-key"
export VOLUME_SIZE_GB="200"

# --- Networking ---
export VPC_ID=""                       # leave blank to use default VPC
export SUBNET_ID=""                    # leave blank to auto-pick a subnet in the VPC
export SECURITY_GROUP_NAME=""
export INSTANCE_NAME=""

# --- Access scoping ---
# Your own IP for RDP access (get via: curl -s https://checkip.amazonaws.com)
export ADMIN_IP_CIDR=""                # e.g. 203.0.113.4/32