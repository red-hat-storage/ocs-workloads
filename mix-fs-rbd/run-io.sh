pgsqlPrefix=$1
logLocation=$2

for i in {1..1}; do 
echo "Running IO on $pgsqlPrefix-$i"
echo "+++++++++++++++++++"

echo " run-workload-pgsql.sh $pgsqlPrefix-$i "
	nohup sh run-workload-pgsql.sh $pgsqlPrefix-$i >$logLocation/$pgsqlPrefix-$i.log & 

echo "IO started in $pgsqlPrefix-$i "
echo "____________________________"
	sleep 5 
done

