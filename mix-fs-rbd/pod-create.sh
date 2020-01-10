pgsqlPrefix=$1
StorageClass=$2

for i in {1..1}; do

echo "Creating pgsql pods in namespace : $pgsqlPrefix-$i"
echo "+++++++++++++++++++"

	sh deploy-pgsql.sh $pgsqlPrefix-$i $StorageClass ;
	date
echo "Pods in namespace : $pgsqlPrefix-$i created"
echo "____________________________"
	sleep 3
done

