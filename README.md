# Reserved Instances Tool
## Introduction
This tool is to manage your Reserved Instances in AWS across all you linked accounts. The tool reads your live configuration (instances and reserved instances) in all your accounts using the AWS API, and produce a set of recommendations to optimize your RI usage. The tool can apply the modifications in your RIs (changing the availability zone, instance type or network allocation) for you, and you can configure it to apply all the recommendations automatically every so often.

## Installation
To install the tool, you should create the necessary roles to let the tool run the AWS API calls. Then you can launch the tool using AWS Beanstalk, I've created a CloudFormation file to facilitate the deployment of the tool.


