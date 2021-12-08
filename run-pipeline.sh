PIPELINE=$1
echo "running pipeline $PIPELINE"
JSON=<<EOF
{
  "@id": "http://localhost/base",
  "@type" : "http://etl.linkedpipes.com/ontology/ExecutionOptions",
  "http://linkedpipes.com/ontology/deleteWorkingData" : true,
  "http://linkedpipes.com/ontology/saveDebugData" : false,
  "http://linkedpipes.com/ontology/logPolicy" : { "@id" : "http://linkedpipes.com/ontology/log/DeleteOnSuccess" }
}'
EOF
curl -X POST -H "Content-Type: application/ld+json" -d "$JSON" http://localhost:8080/resources/executions?pipeline=$PIPELINE
