class SummaryController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:periodic_worker, :health, :s3importer, :populatedb]
  skip_before_filter :authenticate, :only => [:periodic_worker, :health, :s3importer, :populatedb]
  before_filter :authenticate_local, :only => [:periodic_worker, :s3importer, :populatedb]

  include AwsCommon
  def index
    instances = Instance.all
    reserved_instances = ReservedInstance.all
    @summary = Summary.all
  end

  def health
    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  def recommendations
    @recommendations = []
    RecommendationCache.all.each do |recommenation|
      @recommendations << Marshal.load(recommenation.object)
    end
  end

  def apply_recommendations
    recommendations = JSON.parse(params[:recommendations_original], :symbolize_names => true)
    selected = params[:recommendations].split(",")
    selected_recommendations = []
    selected.each do |index|
      selected_recommendations << recommendations[index.to_i]
    end
    apply_recommendation(selected_recommendations)
  end

  def periodic_worker
    if Setup.now_after_nextrefresh
      Setup.update_nextrefresh
      populatedb_data()
    end

    if Setup.now_after_next
      Setup.update_next
      recommendations
      apply_recommendation(@recommendations)
    end
    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  def s3importer
    if Setup.get_importdbr
      bucket = Setup.get_s3bucket
      object = get_dbr_last_date(bucket, Setup.get_processed)
      if !object.nil?
        file_path = download_to_temp(bucket, object)
        file_path_unzip = File.join(Dir.tmpdir, Dir::Tmpname.make_tmpname('dbru',nil))
        Zip::File.open(file_path) do |zip_file|
          zip_file.each do |entry|
            entry.extract(file_path_unzip)
            #content = entry.get_input_stream.read
          end
        end
        f = File.open(file_path_unzip)
        headers = f.gets
        f.close
        regular_account = true
        regular_account = false if headers.include? "BlendedRate"
        file_path_unzip_grep = File.join(Dir.tmpdir, Dir::Tmpname.make_tmpname('dbrug',nil))
        system('grep "RunInstances:" ' + file_path_unzip + ' > ' + file_path_unzip_grep)
        list_instances = {}
        CSV.foreach(file_path_unzip_grep, {headers: true}) do |row|
          # row[10] -> Operation
          # row[21] -> ResourceId (19 for regular accounts)
          # row[2]  -> AccountId
          # row[11] -> AZ
          if !row[10].nil? && row[10].start_with?('RunInstances:') && row[10] != 'RunInstances:0002'
            if regular_account
              list_instances[row[19]] = [row[10], row[2], row[11]]
            else
              list_instances[row[21]] = [row[10], row[2], row[11]]
            end
          end
        end
        amis = get_amis(list_instances, get_account_ids)

        amis.each do |ami_id, operation|
          if Ami.find_by(ami:ami_id).nil?
            new_ami = Ami.new
            new_ami.ami = ami_id
            new_ami.operation = operation
            new_ami.save
          end
        end

        File::unlink(file_path)
        File::unlink(file_path_unzip)
        File::unlink(file_path_unzip_grep)
        Setup.put_processed(object.last_modified) if ENV['MOCK_DATA'].blank?
      end
    end
    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  def log_recommendations
    @recommendations = Recommendation.all
    @failed_recommendations = Modification.all
  end

  def populatedb
    populatedb_data()

    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  private

  def authenticate_local
    render :nothing => true, :status => :unauthorized if !Socket.ip_address_list.map {|x| x.ip_address}.include?(request.remote_ip)
  end
end
