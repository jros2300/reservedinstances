class SetupController < ApplicationController

  #include AwsCommon

  def index
    @regions = Setup.get_regions
    @minutes = Setup.get_minutes
  end

  def change
    Setup.put_regions params[:regions]
    if !params[:minutes].blank?
      Setup.put_minutes params[:minutes] if params[:minutes].to_i >= 30 || params[:minutes].to_i == 0 
    end
    Setup.put_password params[:password] if !params[:password].blank?
    Rails.cache.clear
    redirect_to action: 'index'
  end

  def clear_cache
    Rails.cache.clear
  end

end
