class ReservedInstancesController < ApplicationController
  include AwsCommon

  def index
    @reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
  end
end
