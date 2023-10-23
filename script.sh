#!/bin/bash
# Check for required environment variables
if [ -z "$AWS_S3_BUCKET" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "One or more required environment variables are not set. Quitting."
  exit 1
fi

AWS_SECRET_REGION="${AWS_SECRET_REGION:-eu-south-2}"
BUCKET=$AWS_S3_BUCKET
POLICY="policy${BUCKET}"
USER="${BUCKET}"
REGION="${AWS_SECRET_REGION}"
aws configure --profile s3-actions <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_SECRET_REGION}
text
EOF
cp /home/install/resources/bucket_policy.json .
cp /home/install/resources/cors.json .
create_user () {
    sed -i "s/SOME_USER/$BUCKET/g" 'bucket_policy.json'
    aws iam create-policy --policy-name $POLICY --policy-document file://bucket_policy.json
    aws iam create-user --user-name $USER --region $REGION
    ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`'"$POLICY"'`]'.Arn --output text)
    aws iam attach-user-policy --policy-arn $ARN --user-name $USER
    generate_keys
}

generate_keys () {
    RSP=$(aws iam create-access-key --user-name $USER)
    export BUCKET_ACCESS_ID=$(echo $RSP | jq -r '.AccessKey.AccessKeyId')
    export BUCKET_ACCESS_KEY=$(echo $RSP | jq -r '.AccessKey.SecretAccessKey')
}
#temporarily copying local dirs TODO
populate_bucket () {
    DIREXISTS=$(aws s3 ls s3://$BUCKET/templates/ --region $REGION 2>&1)
    echo "direxists $DIREXISTS"
    if [[ -z $DIREXISTS ]] ; then
        aws s3api put-object --bucket $BUCKET --key templates/ --region $REGION
        echo 'created templates dir'
    fi

    DIREXISTS=$(aws s3 ls s3://$BUCKET/media/public/ --region $REGION 2>&1)

    if [[ -z $DIREXISTS ]] ; then
      aws s3api put-object --bucket $BUCKET --key media/public/ --region $REGION
    fi

    echo 'Copied directories to the bucket'
}
start_proc () {
  if ! aws s3api head-bucket --bucket "$AWS_S3_BUCKET" > /dev/null 2>&1; then
       `aws s3api create-bucket --bucket $BUCKET --create-bucket-configuration LocationConstraint=$REGION --region $REGION`;
  fi

  if ! aws s3api get-bucket-cors --bucket "$AWS_S3_BUCKET" --region "$AWS_SECRET_REGION"> /dev/null 2>&1; then
      echo "Setting CORS configuration to $AWS_SECRET_REGION"
      aws s3api put-bucket-cors --bucket "$AWS_S3_BUCKET" --cors-configuration file://cors.json --region $REGION
  fi

  aws iam get-user --user-name "$AWS_S3_BUCKET" > /dev/null 2>&1 || create_user

  populate_bucket
}
start_proc

aws configure --profile s3-actions <<-EOF > /dev/null 2>&1
null
null
null
text
EOF