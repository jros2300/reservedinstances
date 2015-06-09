class TestsController < ApplicationController

  def index
    account_ids = get_account_ids
  end

  private

  def get_account_ids
    iam = Aws::IAM::Client.new(region: 'eu-west-1')
    metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
    iam_data = Net::HTTP.get( URI.parse( metadata_endpoint + 'iam/info' ) )
    role_name = JSON.parse(iam_data)["InstanceProfileArn"].split("/")[-1]
    pages_policies = iam.list_role_policies({role_name: role_name})
    account_ids = [JSON.parse(iam_data)["InstanceProfileArn"].split(":")[4]]
    pages_policies.each do |role_policies|
       role_policies.policy_names.each do |policy_name|
         pages_policy_data = iam.get_role_policy({role_name: role_name, policy_name: policy_name})
         pages_policy_data.each do |policy_data|
           account_ids += get_account_ids_from_policy(CGI::unescape(policy_data.policy_document))
         end
       end
    end
    #Rails.logger.debug(account_ids)
    return account_ids
  end

  def get_account_ids_from_policy(policy_document)
    policy = JSON.parse(policy_document)
    account_ids = []
    policy["Statement"].each do |statement|
      if statement["Action"].include?("sts:AssumeRole")
        statement["Resource"].each do |arn|
          account_ids << arn.split(":")[4]
        end
      end
    end
    return account_ids
  end
end
