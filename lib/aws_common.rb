module AwsCommon
  require 'csv'
  require 'zip'

  METADATA_ENDPOINT = 'http://169.254.169.254/latest/meta-data/'
  PLATFORMS = {'RunInstances:000g' => 'SUSE Linux', 'RunInstances:0006' => 'Windows with SQL Server Standard', 'RunInstances:0202' => 'Windows with SQL Server Web', 'RunInstances:0010' => 'Red Hat Enterprise Linux', 'RunInstances:0102' => 'Windows with SQL Server Enterprise'}

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
    return [] if !ENV['MOCK_DATA'].blank?
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

  def is_marketplace(product_codes)
    return false if product_codes.blank?
    product_codes.each do |product_code|
      return true if product_code.product_code_type == 'marketplace'
    end
    return false
  end

  def get_instances(regions, account_ids)
    return get_mock_instances if !ENV['MOCK_DATA'].blank?
    Rails.cache.fetch("instances", expires_in: 20.minutes) do
      instances = {}
      current_account_id = get_current_account_id

      amis = {}
      Ami.all.each do |ami|
        amis[ami.ami] = ami.operation
      end

      account_ids.each do |account_id|
        regions.keep_if {|key, value| value }.keys.each do |region|
          if account_id[0] == current_account_id
            ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region))
          else
            role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: account_id[1], role_session_name: "reserved_instances" )
            ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region, credentials: role_credentials))
          end
          ec2.instances.each do |instance|
            if !is_marketplace(instance.product_codes)
              platform = instance.platform.blank? ? "Linux/UNIX" : "Windows"
              platform = PLATFORMS[amis[instance.image_id]] if !amis[instance.image_id].nil? && !PLATFORMS[amis[instance.image_id]].nil?

              instances[instance.id] = {type: instance.instance_type, az: instance.placement.availability_zone, tenancy: instance.placement.tenancy, platform: platform, account_id: account_id[0], vpc: instance.vpc_id.blank? ? "EC2 Classic" : "VPC", ami: instance.image_id} if instance.state.name == 'running'
            end
          end
        end
      end
      instances
    end
  end

  def get_failed_modifications(regions, account_ids)
    return [] if !ENV['MOCK_DATA'].blank?
    Rails.cache.fetch("instances", expires_in: 20.minutes) do
      failed_modifications = []
      current_account_id = get_current_account_id

      account_ids.each do |account_id|
        regions.keep_if {|key, value| value }.keys.each do |region|
          if account_id[0] == current_account_id
            ec2 = Aws::EC2::Client.new(region: region)
          else
            role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: account_id[1], role_session_name: "reserved_instances" )
            ec2 = Aws::EC2::Client.new(region: region, credentials: role_credentials)
          end
          modifications = ec2.describe_reserved_instances_modifications({filters: [ {name: 'status', values: ['failed'] } ] })
          modifications.reserved_instances_modifications.each do |modification|
            failed_modifications << modification.reserved_instances_ids[0].reserved_instances_id
          end
        end
      end

      failed_modifications
    end
  end

  def get_mock_instances
    instances = {}
    amis = {}
    Ami.all.each do |ami|
      amis[ami.ami] = ami.operation
    end
    CSV.foreach('/tmp/instances.csv', headers: true) do |row|
      platform = row[5].blank? ? "Linux/UNIX" : "Windows"
      platform = PLATFORMS[amis[row[9]]] if !amis[row[9]].nil? && !PLATFORMS[amis[row[9]]].nil?

      instances[row[1]] = {type: row[2], az: row[3], tenancy: row[4], platform: platform, account_id: row[6], vpc: row[7].blank? ? "EC2 Classic" : "VPC", ami: row[9]} if row[8] == 'running'
    end
    return instances
  end

  def get_reserved_instances(regions, account_ids)
    return get_mock_reserved_instances if !ENV['MOCK_DATA'].blank?
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
                instances[ri.reserved_instances_id] = {type: ri.instance_type, az: ri.availability_zone, tenancy: ri.instance_tenancy, account_id: account_id[0], count: ri.instance_count, description: ri.product_description, role_arn: account_id[1], end: ri.end, status: 'active'} 
                if supported_platforms[account_id[0]] == 'Classic'
                  instances[ri.reserved_instances_id][:vpc] = ri.product_description.include?("Amazon VPC") ? 'VPC' : 'EC2 Classic'
                else
                  instances[ri.reserved_instances_id][:vpc] = 'VPC'
                end
                instances[ri.reserved_instances_id][:platform] = ri.product_description.sub(' (Amazon VPC)','')
              end
            end
          end
          modifications = ec2.describe_reserved_instances_modifications({filters: [ {name: 'status', values: ['processing'] } ] })
          modifications.reserved_instances_modifications.each do |modification|
            if !instances[modification.reserved_instances_ids[0].reserved_instances_id].nil?
              instances[modification.reserved_instances_ids[0].reserved_instances_id][:status] = 'processing'
              instances[modification.modification_results[0].reserved_instances_id][:status] = 'creating' if !instances[modification.modification_results[0].reserved_instances_id].nil?
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
        instances[row[1]] = {type: row[2], az: row[3], tenancy: row[4], account_id: row[5], count: row[6].to_i, description: row[7], role_arn: '', status: 'active', end: 2.months.from_now} 
        if platforms[row[5]] == 'Classic'
          instances[row[1]][:vpc] = row[7].include?("Amazon VPC") ? 'VPC' : 'EC2 Classic'
        else
          instances[row[1]][:vpc] = 'VPC'
        end

        instances[row[1]][:platform] = row[7].sub(' (Amazon VPC)','')
      end
    end
    return instances
  end

  def apply_recommendation(ri, recommendation)
    region = ri[:az][0..-2]
    if ENV['MOCK_DATA'].blank?
      if ri[:account_id] == get_current_account_id
        ec2 = Aws::EC2::Client.new(region: region)
      else
        role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: ri[:role_arn], role_session_name: "reserved_instances" )
        ec2 = Aws::EC2::Client.new(region: region, credentials: role_credentials)
      end
    end

    conf = {}
    conf[:availability_zone] = recommendation[:az].nil? ? ri[:az] : recommendation[:az] 
    conf[:platform] = recommendation[:vpc].nil? ? (ri[:vpc] == 'VPC' ? 'EC2-VPC' : 'EC2-Classic') : (recommendation[:vpc] == 'VPC' ? 'EC2-VPC' : 'EC2-Classic')
    conf[:instance_count] = recommendation[:count] 
    conf[:instance_type] = recommendation[:type].nil? ? ri[:type] : recommendation[:type] 
    all_confs = [conf]

    #TODO Fill in the request with all the instances not modified in the RI
    if ri[:count] > recommendation[:count] 
      rest_conf = {}
      rest_conf[:availability_zone] = ri[:az]
      rest_conf[:platform] = ri[:vpc] == 'VPC' ? 'EC2-VPC' : 'EC2-Classic'
      rest_conf[:instance_count] = ri[:count] - recommendation[:count] 
      rest_conf[:instance_type] = ri[:type]
      all_confs << rest_conf
    end
    
    ec2.modify_reserved_instances(reserved_instances_ids:[recommendation[:rid]], target_configurations: all_confs) if ENV['MOCK_DATA'].blank?
    log = Recommendation.new
    log.accountid = ri[:account_id]
    log.rid = recommendation[:rid]
    log.az = recommendation[:az] if !recommendation[:az].nil?
    log.vpc = recommendation[:vpc] if !recommendation[:vpc].nil?
    log.instancetype = recommendation[:type] if !recommendation[:type].nil?
    log.count = recommendation[:count]
    log.timestamp = DateTime.now
    log.save
  end

  def get_s3_resource_for_bucket(bucket)
    s3 = Aws::S3::Client.new(region: 'us-east-1')
    begin
      location = s3.get_bucket_location({bucket: bucket})
      s3 = Aws::S3::Client.new(region: location.location_constraint) if location.location_constraint != 'us-east-1'
    rescue
      return nil
    end
    return Aws::S3::Resource.new(client: s3)
  end

  def get_dbr_last_date(bucket, last_processed)
    return 1 if !ENV['MOCK_DATA'].blank?
    last_processed = Time.new(1000) if last_processed.blank?
    s3 = get_s3_resource_for_bucket(bucket)
    Rails.logger.debug "Error" if s3.nil?
    return nil if s3.nil?
    bucket = s3.bucket(bucket)
    last_modified = Time.new(1000)
    last_object = nil
    bucket.objects.each do |object|
      if object.key.include? 'aws-billing-detailed-line-items-with-resources-and-tags'
        if object.last_modified > last_modified && object.last_modified > last_processed
          last_modified = object.last_modified
          last_object = object
        end
      end
    end
    
    return last_object
  end

  def download_to_temp(bucket, object)
    file_path = File.join(Dir.tmpdir, Dir::Tmpname.make_tmpname('dbr',nil))

    if !ENV['MOCK_DATA'].blank?
      FileUtils.cp '/tmp/dbr.csv.zip', file_path
      return file_path
    end

    s3 = get_s3_resource_for_bucket(bucket)
    return nil if s3.nil?
    object.get({response_target: file_path})
    return file_path
  end

  def get_amis(list_instances, account_ids)
    return get_mock_amis(list_instances) if !ENV['MOCK_DATA'].blank?
    amis = {}
    current_account_id = get_current_account_id
    list_instances.each do |instance_id, values|
      # values -> [Operation, AccountId, AZ]
      account_id = nil
      account_ids.each do |acc|
        if acc[0] == values[1]
          account_id = acc
          break
        end
      end

      if !account_id.nil?
        region = values[2][0..-2]
        if account_id[0] == current_account_id
          ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region))
        else
          role_credentials = Aws::AssumeRoleCredentials.new( client: Aws::STS::Client.new(region: region), role_arn: account_id[1], role_session_name: "reserved_instances" )
          ec2 = Aws::EC2::Resource.new(client: Aws::EC2::Client.new(region: region, credentials: role_credentials))
        end
        ec2.instances({instance_ids: [instance_id]}).each do |instance|
          amis[instance.image_id] = values[0]
        end
      end
    end
    return amis
  end

  def get_mock_amis(list_instances)
    amis = {}
    instances = get_mock_instances
    list_instances.each do |instance_id, values|
      # values -> [Operation, AccountId, AZ]
      if !instances[instance_id].nil? && !instances[instance_id][:ami].nil?
        amis[instances[instance_id][:ami]] = values[0]
      end
    end
    return amis
  end

end
