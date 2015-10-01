class SetupController < ApplicationController

  #include AwsCommon

  def index
    @regions = Setup.get_regions
    @minutes = Setup.get_minutes
    @importdbr = Setup.get_importdbr
    @s3bucket = Setup.get_s3bucket
    @processed = Setup.get_processed
  end

  def change
    Setup.put_regions params[:regions]
    if !params[:minutes].blank?
      Setup.put_minutes params[:minutes] if params[:minutes].to_i >= 30 || params[:minutes].to_i == 0 
    end
    Setup.put_password params[:password] if !params[:password].blank?
    Setup.put_importdbr !params[:importdbr].blank?
    Setup.put_s3bucket params[:s3bucket]
    Rails.cache.clear
    redirect_to action: 'index'
  end

  def clear_cache
    Rails.cache.clear
  end

end
