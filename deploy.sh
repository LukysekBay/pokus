#!/usr/bin/env bash

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

configure_aws_cli(){
    aws --version
    aws configure set default.region eu-central-1
    aws configure set default.output json
}

deploy_cluster() {

    family="dev_robeeto-pokus"

    make_task_def
    register_definition
    if [[ $(aws ecs update-service --cluster dev_robeeto-cluster --service dev_robeeto-service --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi

    # wait for older revisions to disappear
    # not really necessary, but nice for demos
    for attempt in {1..30}; do
        if stale=$(aws ecs describe-services --cluster dev_robeeto-cluster --services dev_robeeto-service | \
                       $JQ ".services[0].deployments | .[] | select(.taskDefinition != \"$revision\") | .taskDefinition"); then
            echo "Waiting for stale deployments:"
            echo "$stale"
            sleep 5
        else
            echo "Deployed!"
            return 0
        fi
    done
    echo "Service update took too long."
    return 1
}

make_task_def(){
    task_template='[
	{
	    "name": "dev_robeeto-webapp",
	    "image": "%s.dkr.ecr.eu-central-1.amazonaws.com/dev_robeeto:%s",
	    "essential": true,
	    "memory": 200,
	    "cpu": 10,
	    "portMappings": [
		{
		    "containerPort": 8080,
		    "hostPort": 8080
		}
	    ]
	}
    ]'
    
    task_def=$(printf "$task_template" $AWS_ACCOUNT_ID $CIRCLE_SHA1)
}

push_ecr_image(){
    eval $(aws ecr get-login --region eu-central-1)
                #560613464802.dkr.ecr.eu-central-1.amazonaws.com/dev_robeeto
    docker push 560613464802.dkr.ecr.eu-central-1.amazonaws.com/dev_robeeto:$CIRCLE_SHA1
}

register_definition() {

    if revision=$(aws ecs register-task-definition --container-definitions "$task_def" --family $family | $JQ '.taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

configure_aws_cli
push_ecr_image
deploy_cluster
