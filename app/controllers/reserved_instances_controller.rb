class ReservedInstancesController < ApplicationController
  include AwsCommon

  def index
    @reserved_instances = ReservedInstance.all
  end
end
