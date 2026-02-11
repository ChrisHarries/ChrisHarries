#!/bin/ksh

# Store Subnet IDs into an array
set -A subnets $(aws ec2 describe-subnets | grep SubnetId | awk -F'"' '/SubnetId/ {print $4}')

# Loop through each subnet and modify the attribute
for subnet in "${subnets[@]}"; do
    echo "Modifying subnet: $subnet"
    #aws ec2 modify-subnet-attribute --subnet-id "$subnet" --no-map-public-ip-on-launch
done

