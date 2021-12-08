CURL=`which curl`
if [[ $? -ne 0 ]];then
    echo "curl is required, but not found"
    exit -1
fi
JQ=`which jq`
if [[ $? -ne 0 ]];then
    echo "jq is required, but not found"
    exit -1
fi

PIPELINE=$1
echo "requesting executions"
JSON=`$CURL -X GET -H "Content-Type: application/ld+json" http://localhost:8080/resources/executions`
FINISHED_EXECUTIONS=`echo $JSON | jq '.[] |= {id: ."@graph"[0]."@id", status: ."@graph"[0]."http://etl.linkedpipes.com/ontology/status"[0]."@id"} | map(select( .status == "http://etl.linkedpipes.com/resources/status/finished"))'`
EXECUTION_IDS=`echo $FINISHED_EXECUTIONS | jq -r '.[] | .id'`
for id in $EXECUTION_IDS; do
    echo "removing $id"
    curl -X DELETE $id;
done
