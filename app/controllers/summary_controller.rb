class SummaryController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:periodic_worker, :health, :s3importer, :populatedb]
  skip_before_filter :authenticate, :only => [:periodic_worker, :health, :s3importer, :populatedb]
  before_filter :authenticate_local, :only => [:periodic_worker, :s3importer, :populatedb]

  include AwsCommon
  def index
    instances = Instance.all
    reserved_instances = ReservedInstance.all
    @summary = get_summary(instances,reserved_instances)
  end

  def health
    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  def recommendations
    instances2 = Instance.all
    reserved_instances2 = ReservedInstance.all
    summary = get_summary(instances2,reserved_instances2)

    instances = {}
    instances2.each do |instance|
      instances[instance.instanceid] = {:account_id => instance.accountid, :type => instance.instancetype, :az => instance.az, :platform => instance.platform, :tenancy => instance.tenancy, :vpc => instance.network}
    end

    reserved_instances = {}
    reserved_instances2.each do |ri|
      reserved_instances[ri.reservationid] = {:account_id => ri.accountid, :type => ri.instancetype, :az => ri.az, :tenancy => ri.tenancy, :platform => ri.platform, :vpc => ri.network, :count => ri.count, :end => ri.enddate, :status => ri.status, :offering => ri.offering, :duration => ri.duration}
    end

    continue_iteration = true
    @recommendations = []
    while continue_iteration do
      excess = {}
      # Excess of Instances and Reserved Instances per set of interchangable types
      calculate_excess(summary, excess)
      continue_iteration = iterate_recommendation(excess, instances, summary, reserved_instances, @recommendations)
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
    populatedb_data()

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

  def iterate_recommendation(excess, instances, summary, reserved_instances, recommendations)
    excess.each do |family, elem1|
      elem1.each do |region, elem2|
        elem2.each do |platform, elem3|
          elem3.each do |tenancy, total|
            if total[1] > 0 && total[0] > 0
              # There are reserved instances not used and instances on-demand
              if Setup.get_affinity
                return true if calculate_recommendation(instances, family, region, platform, tenancy, summary, reserved_instances, recommendations, true)
              end
              return true if calculate_recommendation(instances, family, region, platform, tenancy, summary, reserved_instances, recommendations, false)
            end
          end
        end
      end
    end
    return false
  end

  def calculate_recommendation(instances, family, region, platform, tenancy, summary, reserved_instances, recommendations, affinity)
    excess_instance = []

    instances.each do |instance_id, instance|
      if instance[:type].split(".")[0] == family && instance[:az][0..-2] == region && instance[:platform] == platform && instance[:tenancy] == tenancy
        # This instance is of the usable type
        if summary[instance[:type]][instance[:az]][instance[:platform]][instance[:tenancy]][0] > summary[instance[:type]][instance[:az]][instance[:platform]][instance[:tenancy]][1]
          # If for this instance type we have excess of instances
          excess_instance << instance_id
        end
      end
    end

    # First look for AZ changes
    reserved_instances.each do |ri_id, ri|
      if !ri.nil? && ri[:type].split(".")[0] == family && ri[:az][0..-2] == region && ri[:platform] == platform && ri[:tenancy] == tenancy && ri[:status] == 'active'
        # This reserved instance is of the usable type
        if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1] > summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][0]
          # If for this reservation type we have excess of RIs
          # I'm going to look for an instance which can use this reservation
          excess_instance.each do |instance_id|
            # Change with the same type
            if instances[instance_id][:type] == ri[:type] && (!affinity || instances[instance_id][:account_id] == ri[:account_id])
              recommendation = {rid: ri_id, count: 1, orig_count: 1}
              if instances[instance_id][:az] != ri[:az]
                recommendation[:az] = instances[instance_id][:az]
                #Rails.logger.debug("Change in the RI #{ri_id}, to az #{instances[instance_id][:az]}")
              end
              summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1] -= 1
              summary[ri[:type]][instances[instance_id][:az]][ri[:platform]][ri[:tenancy]][1] += 1
              reserved_instances[ri_id][:count] -= 1
              reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
              recommendations << [recommendation]
              return true
            end
          end
        end
      end
    end

    # Now I look for type changes
    # Only for Linux instances
    if platform == 'Linux/UNIX'
      reserved_instances.each do |ri_id, ri|
        if !ri.nil? && ri[:type].split(".")[0] == family && ri[:az][0..-2] == region && ri[:platform] == platform && ri[:tenancy] == tenancy && ri[:status] == 'active'
          # This reserved instance is of the usable type
          if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1] > summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][0]
            # If for this reservation type we have excess of RIs
            # I'm going to look for an instance which can use this reservation
            excess_instance.each do |instance_id|
              if instances[instance_id][:type] != ri[:type] && (!affinity || instances[instance_id][:account_id] == ri[:account_id]) 
                factor_instance = get_factor(instances[instance_id][:type])
                factor_ri = get_factor(ri[:type])
                recommendation = {rid: ri_id}
                recommendation[:type] = instances[instance_id][:type]
                recommendation[:az] = instances[instance_id][:az] if instances[instance_id][:az] != ri[:az]
                #recommendation[:vpc] = instances[instance_id][:vpc] if instances[instance_id][:vpc] != ri[:vpc]
                if factor_ri > factor_instance
                  # Split the RI
                  new_instances = factor_ri / factor_instance
                  recommendation[:count] = new_instances.to_i
                  recommendation[:orig_count] = 1
                  #Rails.logger.debug("Change in the RI #{ri_id}, split in #{new_instances} to type #{instances[instance_id][:type]}")

                  summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1] -= 1
                  summary[instances[instance_id][:type]][instances[instance_id][:az]][ri[:platform]][ri[:tenancy]][1] += new_instances
                  reserved_instances[ri_id][:count] -= 1
                  reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
                  recommendations << [recommendation]
                  return true
                else
                  # Join the RI, I need more RIs to complete the needed factor of the instance
                  ri_needed = factor_instance / factor_ri
                  if (ri[:count] > ri_needed) && (summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1]-ri_needed) >= summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][0]
                    # We only need join part of this RI to reach to the needed number of instances
                    recommendation[:count] = 1
                    recommendation[:orig_count] = ri_needed
                    summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1] -= ri_needed
                    summary[instances[instance_id][:type]][instances[instance_id][:az]][ri[:platform]][ri[:tenancy]][1] += 1
                    reserved_instances[ri_id][:count] -= ri_needed
                    reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
                    recommendations << [recommendation]
                    return true
                  else
                    # We need to find more RIs to join with this one
                    list_ris = [ri]
                    list_ri_ids = [ri_id]
                    count_ri = [(summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][1]-summary[ri[:type]][ri[:az]][ri[:platform]][ri[:tenancy]][0]), ri[:count]].min
                    list_ri_counts = [count_ri]
                    factor_ri_needed = factor_instance - (factor_ri*count_ri)

                    reserved_instances.each do |ri_id2, ri2|
                      if !ri2.nil? && ri2[:type].split(".")[0] == family && ri2[:az][0..-2] == region && ri2[:platform] == platform && ri2[:tenancy] == tenancy && ri2[:status] == 'active' && ri2[:account_id] == ri[:account_id] && !list_ri_ids.include?(ri_id2) && ri[:end].change(:min => 0) == ri2[:end].change(:min => 0) && ri[:offering] == ri2[:offering] && ri[:duration] == ri2[:duration]
                        if summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][1] > summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][0]
                          factor_ri2 = get_factor(ri2[:type])
                          if factor_ri2 < factor_instance
                            list_ris << ri2
                            list_ri_ids << ri_id2
                            count_ri = [(summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][1]-summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][0]), ri2[:count]].min
                            if (factor_ri2*count_ri) > factor_ri_needed
                              count_ri = factor_ri_needed/factor_ri2
                              list_ri_counts << count_ri
                              factor_ri_needed -= factor_ri2*count_ri
                              break
                            else
                              list_ri_counts << count_ri
                              factor_ri_needed -= factor_ri2*count_ri
                            end
                          end
                        end
                      end
                    end
                    if factor_ri_needed == 0
                      recommendation_complex = []
                      summary[instances[instance_id][:type]][instances[instance_id][:az]][instances[instance_id][:platform]][instances[instance_id][:tenancy]][1] += 1
                      list_ris.each_index do |i|
                        recommendation = {rid: list_ri_ids[i]}
                        recommendation[:type] = instances[instance_id][:type]
                        recommendation[:az] = instances[instance_id][:az] if instances[instance_id][:az] != list_ris[i][:az]
                        recommendation[:count] = 1
                        recommendation[:orig_count] = list_ri_counts[i]
                        summary[list_ris[i][:type]][list_ris[i][:az]][list_ris[i][:platform]][list_ris[i][:tenancy]][1] -= list_ri_counts[i]
                        reserved_instances[list_ri_ids[i]][:count] -= list_ri_counts[i]
                        reserved_instances[list_ri_ids[i]] = nil if reserved_instances[list_ri_ids[i]][:count] == 0
                        recommendation_complex << recommendation
                      end
                      recommendations << recommendation_complex
                      return true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    return false

  end

  def get_total_compatible_ri_factor(ri, reserved_instances, summary)
    # Return the total execess of ri with the same end date, compatible to join
    total_number = 0
    reserved_instances.each do |ri2_id, ri2|
      if !ri2.nil? && ri[:type].split(".")[0] == ri2[:type].split(".")[0] && ri[:az][0..-2] == ri2[:az][0..-2] && ri[:platform] == ri2[:platform] && ri[:tenancy] == ri2[:tenancy] && ri2[:status] == 'active' && ri[:end] == ri2[:end]
        # This reserved instance is of the same type
        if summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][1] > summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][0]
          # If for this reservation type we have excess of RIs
          total_number += get_factor(ri2[:type]) * (summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][1] - summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][0])
        end
      end
    end
    return total_number
  end

  def get_combination_ris(list_ris, value_expected)
    list_ris.each_index do |i|
      ri = list_ris[i]
      ri_factor = get_factor(ri[:type])
      return [ri] if value_expected == ri_factor
      if value_expected > ri_factor
        new_list = Array.new(list_ris)
        new_list = list_ris.delete_at(i)
        new_combination = get_combination_ris(new_list, value_expected-ri_factor)
        return new_combination << ri if !new_combination.nil?
      end
    end
    return nil
  end

  def get_list_possible_ris(ri, reserved_instances, summary)
    # Return the list of ri with the same end date, compatible to join
    possible_ris = []
    reserved_instances.each do |ri2_id, ri2|
      if !ri2.nil? && ri[:type].split(".")[0] == ri2[:type].split(".")[0] && ri[:az][0..-2] == ri2[:az][0..-2] && ri[:platform] == ri2[:platform] && ri[:tenancy] == ri2[:tenancy] && ri2[:status] == 'active' && ri[:end] == ri2[:end]
        # This reserved instance is of the same type
        if summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][1] > summary[ri2[:type]][ri2[:az]][ri2[:platform]][ri2[:tenancy]][0]
          # If for this reservation type we have excess of RIs
          possible_ris << ri2
        end
      end
    end
    return possible_ris
  end

  def calculate_excess(summary, excess)
    # Group the excess of RIs and instances per family and region
    # For example, for m3 in eu-west-1, it calculate the total RIs not used and the total instances not assigned to an RI (in any family type and AZ)
    summary.each do |type, elem1|
      elem1.each do |az, elem2| 
        elem2.each do |platform, elem3| 
          elem3.each do |tenancy, total|
            if total[0] != total[1]
              family = type.split(".")[0]
              region = az[0..-2]
              excess[family] = {} if excess[family].nil?
              excess[family][region] = {} if excess[family][region].nil?
              excess[family][region][platform] = {} if excess[family][region][platform].nil?
              excess[family][region][platform][tenancy] = [0,0] if excess[family][region][platform][tenancy].nil?
              factor = get_factor(type)
              if total[0] > total[1]
                # [0] -> Total of instances without a reserved instance
                excess[family][region][platform][tenancy][0] += (total[0]-total[1])*factor
              else
                # [1] -> Total of reserved instances not used
                excess[family][region][platform][tenancy][1] += (total[1]-total[0])*factor
              end
            end
          end
        end
      end
    end
  end

  def get_summary(instances, reserved_instances)
    summary = {}

    instances.each do |instance|
      summary[instance.instancetype] = {} if summary[instance.instancetype].nil?
      summary[instance.instancetype][instance.az] = {} if summary[instance.instancetype][instance.az].nil?
      summary[instance.instancetype][instance.az][instance.platform] = {} if summary[instance.instancetype][instance.az][instance.platform].nil?
      summary[instance.instancetype][instance.az][instance.platform][instance.tenancy] = [0,0] if summary[instance.instancetype][instance.az][instance.platform][instance.tenancy].nil?
      summary[instance.instancetype][instance.az][instance.platform][instance.tenancy][0] += 1
    end

    reserved_instances.each do |ri|
      if ri.status == 'active'
        summary[ri.instancetype] = {} if summary[ri.instancetype].nil?
        summary[ri.instancetype][ri.az] = {} if summary[ri.instancetype][ri.az].nil?
        summary[ri.instancetype][ri.az][ri.platform] = {} if summary[ri.instancetype][ri.az][ri.platform].nil?
        summary[ri.instancetype][ri.az][ri.platform][ri.tenancy] = [0,0] if summary[ri.instancetype][ri.az][ri.platform][ri.tenancy].nil?
        summary[ri.instancetype][ri.az][ri.platform][ri.tenancy][1] += ri.count
      end
    end

    return summary
  end

  def authenticate_local
    render :nothing => true, :status => :unauthorized if !Socket.ip_address_list.map {|x| x.ip_address}.include?(request.remote_ip)
  end
end
