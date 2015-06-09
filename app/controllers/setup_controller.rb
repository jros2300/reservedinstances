class SetupController < ApplicationController

  #include AwsCommon

  def index
    @regions = Setup.get_regions
  end

  def change
    Setup.put_regions params[:regions]
    redirect_to action: 'index'
  end

end
