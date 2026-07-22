#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?Set in env.sh}"
: "${SG_ID:?Set in env.sh}"
: "${IBM_GATEWAY_IP_1:?Set in env.sh}"
: "${IBM_GATEWAY_IP_2:?Set in env.sh}"

REGION_FLAG="--region $AWS_REGION"

# Inbound: IKE/NAT-T from IBM Cloud gateway IPs only
for GW_IP in "$IBM_GATEWAY_IP_1" "$IBM_GATEWAY_IP_2"; do
  aws ec2 authorize-security-group-ingress $REGION_FLAG \
    --group-id "$SG_ID" --protocol udp --port 500 --cidr "${GW_IP}/32"
  aws ec2 authorize-security-group-ingress $REGION_FLAG \
    --group-id "$SG_ID" --protocol udp --port 4500 --cidr "${GW_IP}/32"
done

# # Outbound: remove default allow-all, restrict to same two gateway IPs
# aws ec2 revoke-security-group-egress $REGION_FLAG \
#   --group-id "$SG_ID" --protocol -1 --cidr 0.0.0.0/0

# for GW_IP in "$IBM_GATEWAY_IP_1" "$IBM_GATEWAY_IP_2"; do
#   aws ec2 authorize-security-group-egress $REGION_FLAG \
#     --group-id "$SG_ID" --protocol udp --port 500 --cidr "${GW_IP}/32"
#   aws ec2 authorize-security-group-egress $REGION_FLAG \
#     --group-id "$SG_ID" --protocol udp --port 4500 --cidr "${GW_IP}/32"
# done