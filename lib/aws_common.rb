module AwsCommon
  require 'csv'

  METADATA_ENDPOINT = 'http://169.254.169.254/latest/meta-data/'
  def get_regions
    return ['eu-west-1', 'us-east-1', 'us-west-1', 'us-west-2']
  end

  def get_current_account_id
    Rails.cache.fetch("current_account_id", expires_in: 24.hours) do
      iam_data = Net::HTTP.get( URI.parse( METADATA_ENDPOINT + 'iam/info' ) )
      return JSON.parse(iam_data)["InstanceProfileArn"].split(":")[4]
    end
  end

  def get_account_ids
    return [['180179741841',''],['269898447219',''],['297144392530',''],['310028733292',''],['416743795203',''],['454226772460',''],['463879194824',''],['537205908513',''],['602794641042',''],['639212290688',''],['642900864480',''],['658243788766',''],['715140769385',''],['795478861756',''],['796285877930',''],['988851520197','']]
    Rails.cache.fetch("account_ids", expires_in: 1.hours) do
      iam = Aws::IAM::Client.new(region: 'eu-west-1')
      iam_data = Net::HTTP.get( URI.parse( METADATA_ENDPOINT + 'iam/info' ) )
      role_name = JSON.parse(iam_data)["InstanceProfileArn"].split("/")[-1]
      pages_policies = iam.list_role_policies({role_name: role_name})
      account_ids = [[get_current_account_id,""]]
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
  end

  def get_account_ids_from_policy(policy_document)
    policy = JSON.parse(policy_document)
    account_ids = []
    policy["Statement"].each do |statement|
      if statement["Action"].include?("sts:AssumeRole")
        statement["Resource"].each do |arn|
          account_ids << [arn.split(":")[4], arn]
        end
      end
    end
    return account_ids
  end

  def get_instances(regions, account_ids)
    return get_mock_instances
    Rails.cache.fetch("instances", expires_in: 20.minutes) do
      instances = {}
      current_account_id = get_current_account_id

      account_ids.each do |account_id|
        regions.keep_if {|key, value| value }.keys.each do |region|
          if account_id[0] == current_account_id
            ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region))
          else
            role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: account_id[1], role_session_name: "reserved_instances" )
            ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region, credentials: role_credentials))
          end
          ec2.instances.each do |instance|
            instances[instance.id] = {type: instance.instance_type, az: instance.placement.availability_zone, tenancy: instance.placement.tenancy, platform: instance.platform.blank? ? "Linux" : "Windows", account_id: account_id[0], vpc: instance.vpc_id.blank? ? "EC2 Classic" : "VPC"} if instance.state.name == 'running'
          end
        end
      end
      instances
    end
  end

  def get_mock_instances
    instances = {}
    CSV.foreach('/tmp/instances.csv', headers: true) do |row|
      instances[row[1]] = {type: row[2], az: row[3], tenancy: row[4], platform: row[5].blank? ? "Linux" : "Windows", account_id: row[6], vpc: row[7].blank? ? "EC2 Classic" : "VPC"} if row[8] == 'running'
    end
    return instances
  end

  def get_reserved_instances(regions, account_ids)
    return get_mock_reserved_instances
    Rails.cache.fetch("reserved_instances", expires_in: 20.minutes) do
      instances = {}
      current_account_id = get_current_account_id

      supported_platforms = {}

      account_ids.each do |account_id|
        regions.keep_if {|key, value| value }.keys.each do |region|
          if account_id[0] == current_account_id
            ec2 = Aws::EC2::Client.new(region: region)
          else
            role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: account_id[1], role_session_name: "reserved_instances" )
            ec2 = Aws::EC2::Client.new(region: region, credentials: role_credentials)
          end
          if supported_platforms[account_id[0]].nil?
            platforms = ec2.describe_account_attributes(attribute_names: ["supported-platforms"])
            platforms.each do |platform|
              platform.account_attributes.each do |attribute|
                supported_platforms[account_id[0]] = attribute.attribute_values.size > 1 ? "Classic" : "VPC" if attribute.attribute_name == 'supported-platforms'
              end
            end
          end

          reserved_instances = ec2.describe_reserved_instances
          reserved_instances.each do |reserved_instance|
            reserved_instance.reserved_instances.each do |ri|
              if ri.state == 'active'
                instances[ri.reserved_instances_id] = {type: ri.instance_type, az: ri.availability_zone, tenancy: ri.instance_tenancy, account_id: account_id[0], count: ri.instance_count, description: ri.product_description, role_arn: account_id[1]} 
                if supported_platforms[account_id[0]] == 'Classic'
                  instances[ri.reserved_instances_id][:vpc] = ri.product_description.include?("Amazon VPC") ? 'VPC' : 'EC2 Classic'
                else
                  instances[ri.reserved_instances_id][:vpc] = 'VPC'
                end
                if ri.product_description.include? "Linux/UNIX"
                  instances[ri.reserved_instances_id][:platform] = 'Linux'
                elsif ri.product_description.include?("Windows") && !ri.product_description.include?("SQL Server")
                  instances[ri.reserved_instances_id][:platform] = 'Windows'
                else
                  instances[ri.reserved_instances_id] = nil
                end
              end
            end
          end
        end
      end

      instances
    end
  end

  def get_mock_reserved_instances
    instances = {}
    platforms = {}
    CSV.foreach('/tmp/platforms.csv', headers: true) do |row|
      platforms[row[2]] = row[1]
    end
    CSV.foreach('/tmp/ri.csv', headers: true) do |row|
      if row[8] == 'active'
        instances[row[1]] = {type: row[2], az: row[3], tenancy: row[4], account_id: row[5], count: row[6].to_i, description: row[7], role_arn: ''} 
        if platforms[row[5]] == 'Classic'
          instances[row[1]][:vpc] = row[7].include?("Amazon VPC") ? 'VPC' : 'EC2 Classic'
        else
          instances[row[1]][:vpc] = 'VPC'
        end
        if row[7].include? "Linux/UNIX"
          instances[row[1]][:platform] = 'Linux'
        elsif row[7].include?("Windows") && !row[7].include?("SQL Server")
          instances[row[1]][:platform] = 'Windows'
        else
          instances[row[1]] = nil
        end
      end
    end
    return instances
  end

  def apply_recommendation(ri, recommendation)
    region = ri[:az][0..-2]
    if ri[:account_id] == get_current_account_id
      ec2 = Aws::EC2::Client.new(region: region)
    else
      role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: ri[:role_arn], role_session_name: "reserved_instances" )
      ec2 = Aws::EC2::Client.new(region: region, credentials: role_credentials)
    end
    conf = {}
    conf[:availability_zone] = recommendation["az"].nil? ? ri[:az] : recommendation["az"] 
    conf[:platform] = recommendation["vpc"].nil? ? (ri[:vpc] == 'VPC' ? 'EC2-VPC' : 'EC2-Classic') : (recommendation["vpc"] == 'VPC' ? 'EC2-VPC' : 'EC2-Classic')
    conf[:instance_count] = recommendation["count"] 
    conf[:instance_type] = recommendation["type"].nil? ? ri[:type] : recommendation["type"] 
    #Rails.logger.debug(conf)
    ec2.modify_reserved_instances(reserved_instances_ids:[recommendation["rid"]], target_configurations: [conf])
  end
end
