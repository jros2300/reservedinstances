class InstancesController < ApplicationController
  include AwsCommon

  def index
    @instances = get_instances(Setup.get_regions, get_account_ids)
  end
end
