PIPELINE=$1
echo "running pipeline $PIPELINE"
# based on https://github.com/linkedpipes/etl/wiki/Pipeline-execution-with-curl
JSON=<<EOF
{
  "@id": "http://localhost/base",
  "@type" : "http://etl.linkedpipes.com/ontology/ExecutionOptions",
  "http://linkedpipes.com/ontology/deleteWorkingData" : true,
  "http://linkedpipes.com/ontology/saveDebugData" : false,
  "http://linkedpipes.com/ontology/logPolicy" : { "@id" : "http://linkedpipes.com/ontology/log/DeleteOnSuccess" }
}'
EOF

TOKEN=$2
# with auth via nginx using ld+json
#curl -X POST -H "Authorization: Basic $TOKEN" -H "Content-Type: application/ld+json" -d "$JSON" http://localhost:8080/resources/executions?pipeline=$PIPELINE
# with auth via nginx using multipart form
curl -X POST -H "Authorization: Basic $TOKEN"  -H "Content-Type: multipart/form-data" -F "configuration=@/opt/linkedpipes-utils/options.jsonld" http://localhost:8080/resources/executions?pipeline=$PIPELINE
# without auth direct to frontend using ld+json
#curl -X POST  -H "Content-Type: application/ld+json" -d "$JSON" http://localhost:9080/resources/executions?pipeline=$PIPELINE
