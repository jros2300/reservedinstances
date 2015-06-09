class SetupController < ApplicationController

  #include AwsCommon

  def index
    @regions = Setup.get_regions
  end

  def change
    Setup.put_regions params[:regions]
    Rails.cache.clear
    redirect_to action: 'index'
  end

end
