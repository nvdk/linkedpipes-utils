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
TOKEN=$2
echo "requesting executions"
JSON=`$CURL -X GET -H "Content-Type: application/ld+json" -H "Authorization: Basic $TOKEN" http://localhost:8080/resources/executions`
FINISHED_EXECUTIONS=`echo $JSON | jq '.[] |= {id: ."@graph"[0]."@id", status: ."@graph"[0]."http://etl.linkedpipes.com/ontology/status"[0]."@id"} | map(select( .status == "http://etl.linkedpipes.com/resources/status/failed"))'`
EXECUTION_IDS=`echo $FINISHED_EXECUTIONS | jq -r '.[] | .id'`
for id in $EXECUTION_IDS; do
    echo "removing $id"
    curl -H "Authorization: Basic $TOKEN" -X DELETE http://srvlodlppr01.gentgrp.gent.be:8080/api/v1/executions?iri=$id;
done
