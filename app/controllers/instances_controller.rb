class InstancesController < ApplicationController
  include AwsCommon

  def index
    @instances = Instance.all
  end
end
