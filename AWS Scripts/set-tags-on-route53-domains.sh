#!/bin/bash

list=($(aws route53 list-hosted-zones | grep Id | awk -F ' ' '{print $2}' | awk '{ print substr($0, 13)}' | cut -c2- | rev | cut -c3- | rev))

for i in "${list[@]}"
do
echo $i
aws route53 change-tags-for-resource --resource-id $i --resource-type hostedzone --add-tags Key=mission,Value=domains
done
