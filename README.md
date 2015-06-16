# Reserved Instances Tool
## Introduction
This tool is to manage your Reserved Instances in AWS across all you linked accounts. The tool reads your live configuration (instances and reserved instances) in all your accounts using the AWS API, and produce a set of recommendations to optimize your RI usage. The tool can apply the modifications in your RIs (changing the availability zone, instance type or network allocation) for you, and you can configure it to apply all the recommendations automatically every so often.

## Installation
To install the tool, you should create the necessary roles to let the tool run the AWS API calls. Then you can launch the tool using AWS Beanstalk, I've created a CloudFormation file to facilitate the deployment of the tool.

You can use the tool with one account, or a group of accounts (linked accounts).

If you have multiple accounts, you can deploy the tool in any of them (let's call the account where you're going to deploy the tool account1), then you should create a role in each account. Go to the AWS Console, and select the Identity & Access Management (IAM) service. Select Roles and create a new one.

For each account where you're not going to deploy the tool (so for all but account1), name the role "reservedinstances", select the option "Role for Cross-Account Access"and select "Provide access between AWS accounts you own". Introduce the account id for account1. Create the rol and then attach this policy to it:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1433771637000",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeInstances",
                "ec2:DescribeReservedInstances",
                "ec2:DescribeReservedInstancesListings",
                "ec2:DescribeReservedInstancesModifications",
                "ec2:DescribeReservedInstancesOfferings",
                "ec2:DescribeAccountAttributes",
                "ec2:ModifyReservedInstances"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```

If you only have one account, or if you have multiple accounts in the account1, create a new role. Name the role "reservedisntances", select the option "Amazon EC2" in the "AWS Service Roles" list. Create the rol and then attach two policies to it, the previous and and this one:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1433772347001",
            "Effect": "Allow",
            "Action": [
                "iam:ListRolePolicies",
                "iam:GetRolePolicy"
            ],
            "Resource": [
                "arn:aws:iam::<account1 id>:role/reservedinstances"
            ]
        },
        {
            "Sid": "Stmt1433772347000",
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": [
                "arn:aws:iam::<account2 id>:role/reservedinstances",
                "arn:aws:iam::<account3 id>:role/reservedinstances",
                "arn:aws:iam::<account4 id>:role/reservedinstances",
                "arn:aws:iam::<account5 id>:role/reservedinstances",
                "arn:aws:iam::<account6 id>:role/reservedinstances"
            ]
        },
        {
          "Sid": "QueueAccess",
          "Action": [
            "sqs:ChangeMessageVisibility",
            "sqs:DeleteMessage",
            "sqs:ReceiveMessage",
            "sqs:SendMessage"
          ],
          "Effect": "Allow",
          "Resource": "arn:aws:sqs:<region>:<account1 id>:ritoolqueue"
      },
      {
          "Sid": "MetricsAccess",
          "Action": [
            "cloudwatch:PutMetricData"
          ],
          "Effect": "Allow",
          "Resource": "*"
      },
      {
          "Sid": "BucketAccess",
          "Action": [
            "s3:Get*",
            "s3:List*",
            "s3:PutObject"
          ],
          "Effect": "Allow",
          "Resource": [
            "arn:aws:s3:::elasticbeanstalk-*-<account1 id>/*",
            "arn:aws:s3:::elasticbeanstalk-*-<account1 id>-*/*"
          ]
      },
      {
          "Sid": "DynamoPeriodicTasks",
          "Action": [
            "dynamodb:BatchGetItem",
            "dynamodb:BatchWriteItem",
            "dynamodb:DeleteItem",
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:Query",
            "dynamodb:Scan",
            "dynamodb:UpdateItem"
          ],
          "Effect": "Allow",
          "Resource": [
            "arn:aws:dynamodb:*:<account1 id>:table/*-stack-AWSEBWorkerCronLeaderRegistry*"
          ]
      }
    ]
}
```

You can add as many accouts as you need to the policy. You can use all your linked accounts or a subset of them.

You also need:

* 1 VPC
* 2 Subnets
* 1 KeyPair
* 1 SSL Cert ARN (http://docs.aws.amazon.com/IAM/latest/UserGuide/ManagingServerCerts.html)
* 1 Rails Secret Key (You can generate it in any computer with Ruby installed, just run:
  * $ irb
  * >> require 'securerandom'
  * >> SecureRandom.hex(64)

You need also this application in S3, you can download the last version and upload to any S3 bucket, or you can use the default values and use the one I maintain.

Then you should go to the console in the account1, and select the service CloudFormation.




