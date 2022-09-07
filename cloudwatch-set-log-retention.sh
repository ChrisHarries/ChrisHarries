
log_groups=( $(aws logs describe-log-groups | grep logGroupName | awk -F ' ' '{print $2}' | cut -c2- | rev | cut -c3- | rev | sed '/ConfigRulesTempla/d' ) )

length=${#log_groups[@]}
i=0

while [ $i -lt $length ] 
do
	aws logs put-retention-policy --log-group-name ${log_groups[$i]} --retention-in-days 365
	aws logs describe-log-groups --log-group-name ${log_groups[$i]} | grep retentionInDays
	let i++
done
