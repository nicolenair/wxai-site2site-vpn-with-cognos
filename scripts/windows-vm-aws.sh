#!/usr/bin/env bash
set -euo pipefail

# Provisions a Windows Server EC2 instance sized for Cognos, with a 1:1
# Elastic IP (required for IPsec S2S — no NAT/PAT) and a security group
# scoped for RDP admin access + IBM Cloud VPN gateway peering.
#
# Requires: AWS CLI v2, credentials configured, source env.sh first.

: "${AWS_REGION:?Set in env.sh}"
: "${INSTANCE_TYPE:?Set in env.sh}"
: "${WINDOWS_AMI_NAME:?Set in env.sh}"
: "${KEY_PAIR_NAME:?Set in env.sh}"
: "${SECURITY_GROUP_NAME:?Set in env.sh}"
: "${INSTANCE_NAME:?Set in env.sh}"
: "${ADMIN_IP_CIDR:?Set in env.sh}"

REGION_FLAG="--region $AWS_REGION"

echo "== 1. VPC / subnet =="
if [ -z "${VPC_ID:-}" ]; then
  VPC_ID=$(aws ec2 describe-vpcs $REGION_FLAG \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" --output text)
fi
echo "Using VPC: $VPC_ID"

if [ -z "${SUBNET_ID:-}" ]; then
  SUBNET_ID=$(aws ec2 describe-subnets $REGION_FLAG \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" \
    --query "Subnets[0].SubnetId" --output text)
fi
echo "Using Subnet: $SUBNET_ID"

echo "== 2. Key pair =="
if ! aws ec2 describe-key-pairs $REGION_FLAG --key-names "$KEY_PAIR_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair $REGION_FLAG \
    --key-name "$KEY_PAIR_NAME" \
    --query "KeyMaterial" --output text > "${KEY_PAIR_NAME}.pem"
  chmod 600 "${KEY_PAIR_NAME}.pem"
  echo "Created key pair, saved to ${KEY_PAIR_NAME}.pem"
else
  echo "Key pair $KEY_PAIR_NAME already exists, skipping"
fi

echo "== 3. Security group =="
SG_ID=$(aws ec2 describe-security-groups $REGION_FLAG \
  --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  SG_ID=$(aws ec2 create-security-group $REGION_FLAG \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "Cognos S2S VPN peer - RDP admin + IBM Cloud IKE/IPsec" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
  echo "Created security group: $SG_ID"

  # RDP, admin IP only
  aws ec2 authorize-security-group-ingress $REGION_FLAG \
    --group-id "$SG_ID" --protocol tcp --port 3389 --cidr "$ADMIN_IP_CIDR"

  # Default egress (all outbound) is already open on a new SG - narrow
  # this later if you want the same lockdown pattern used on the IBM
  # Cloud side (egress restricted to just the two gateway IPs).
else
  echo "Security group $SECURITY_GROUP_NAME already exists: $SG_ID"
fi

echo "== 4. Latest Windows Server AMI =="
AMI_ID=$(aws ec2 describe-images $REGION_FLAG \
  --owners amazon \
  --filters "Name=name,Values=$WINDOWS_AMI_NAME" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text)
echo "Using AMI: $AMI_ID"

echo "== 5. Launch instance =="
INSTANCE_ID=$(aws ec2 run-instances $REGION_FLAG \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_PAIR_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE_GB},\"VolumeType\":\"gp3\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query "Instances[0].InstanceId" --output text)
echo "Launched instance: $INSTANCE_ID"

echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running $REGION_FLAG --instance-ids "$INSTANCE_ID"

echo "== 6. Allocate and associate Elastic IP (1:1 public IP - required for IPsec) =="
ALLOC_ID=$(aws ec2 allocate-address $REGION_FLAG \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${INSTANCE_NAME}-eip}]" \
  --query "AllocationId" --output text)

aws ec2 associate-address $REGION_FLAG \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$ALLOC_ID" >/dev/null

PUBLIC_IP=$(aws ec2 describe-addresses $REGION_FLAG \
  --allocation-ids "$ALLOC_ID" \
  --query "Addresses[0].PublicIp" --output text)

echo ""
echo "== Done =="
echo "Instance ID:  $INSTANCE_ID"
echo "Public IP:    $PUBLIC_IP   (use this as PEER_PUBLIC_IP / --Destination in the S2S setup)"
echo "Key file:     ${KEY_PAIR_NAME}.pem"
echo ""
echo "Get the Windows Administrator password with:"
echo "  aws ec2 get-password-data $REGION_FLAG --instance-id $INSTANCE_ID --priv-launch-key ${KEY_PAIR_NAME}.pem"