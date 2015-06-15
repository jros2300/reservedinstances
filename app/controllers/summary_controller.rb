class SummaryController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:periodic_worker]

  include AwsCommon
  def index
    instances = get_instances(Setup.get_regions, get_account_ids)
    reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
    @summary = get_summary(instances,reserved_instances)
  end

  def recommendations
    instances = get_instances(Setup.get_regions, get_account_ids)
    reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
    summary = get_summary(instances,reserved_instances)

    continue_iteration = true
    @recommendations = []
    while continue_iteration do
      excess = {}
      # Excess of Instances and Reserved Instances per set of interchangable types
      calculate_excess(summary, excess)
      continue_iteration = iterate_recommendation(excess, instances, summary, reserved_instances, @recommendations)
    end
    #@recommendations = consolidate_recommendations(@recommendations)
  end

  def apply_recommendations
    recommendations = JSON.parse(params[:recommendations_original], :symbolize_names => true)
    reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
    selected = params[:recommendations].split(",")
    selected_recommendations = []
    selected.each do |index|
      selected_recommendations << recommendations[index.to_i]
    end
    selected_recommendations = consolidate_recommendations(selected_recommendations)
    selected_recommendations.each do |recommendation|
      ri = reserved_instances[recommendation[:rid]]
      apply_recommendation(ri, recommendation)
    end
  end

  def periodic_worker
    if Setup.now_after_next
      Setup.update_next
      Rails.cache.clear
      recommendations
      reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
      @recommendations = consolidate_recommendations(@recommendations)
      @recommendations.each do |recommendation|
        ri = reserved_instances[recommendation[:rid]]
        apply_recommendation(ri, recommendation)
      end
    end
    render :nothing => true, :status => 200, :content_type => 'text/html'
  end

  def log_recommendations
    @recommendations = Recommendation.all
  end

  private

  def consolidate_recommendations(recommendations)
    new_recommendations = []
    recommendations.each do |recommendation|
      added = false
      new_recommendations.each do |new_recommendation|
        if new_recommendation[:rid]==recommendation[:rid] && new_recommendation[:az]==recommendation[:az] && new_recommendation[:type]==recommendation[:type] && new_recommendation[:vpc]==recommendation[:vpc] 
          new_recommendation[:count] += recommendation[:count]
          added = true
        end
      end
      new_recommendations << {rid: recommendation[:rid], count: recommendation[:count], az: recommendation[:az], type: recommendation[:type], vpc: recommendation[:vpc]} if !added
    end
    return new_recommendations
  end

  def iterate_recommendation(excess, instances, summary, reserved_instances, recommendations)
    excess.each do |family, elem1|
      elem1.each do |region, elem2|
        elem2.each do |platform, elem3|
          elem3.each do |tenancy, total|
            if total[1] > 0 && total[0] > 0
              # There are reserved instances not used and instances on-demand
              return true if calculate_recommendation(instances, family, region, platform, tenancy, summary, reserved_instances, recommendations)
            end
          end
        end
      end
    end
    return false
  end

  def calculate_recommendation(instances, family, region, platform, tenancy, summary, reserved_instances, recommendations)
    excess_instance = []

    instances.each do |instance_id, instance|
      if instance[:type].split(".")[0] == family && instance[:az][0..-2] == region && instance[:platform] == platform && instance[:tenancy] == tenancy
        # This instance is of the usable type
        if summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]][instance[:tenancy]][0] > summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]][instance[:tenancy]][1]
          # If for this instance type we have excess of instances
          excess_instance << instance_id
        end
      end
    end

    # First look for AZ or VPC changes
    reserved_instances.each do |ri_id, ri|
      if !ri.nil? && ri[:type].split(".")[0] == family && ri[:az][0..-2] == region && ri[:platform] == platform && ri[:tenancy] == tenancy
        # This reserved instance is of the usable type
        if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] > summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][0]
          # If for this reservation type we have excess of RIs
          # I'm going to look for an instance which can use this reservation
          excess_instance.each do |instance_id|
            # Change with the same type
            if instances[instance_id][:type] == ri[:type] 
              recommendation = {rid: ri_id, count: 1}
              if instances[instance_id][:az] != ri[:az]
                recommendation[:az] = instances[instance_id][:az]
                #Rails.logger.debug("Change in the RI #{ri_id}, to az #{instances[instance_id][:az]}")
              end
              if instances[instance_id][:vpc] != ri[:vpc]
                recommendation[:vpc] = instances[instance_id][:vpc]
                #Rails.logger.debug("Change in the RI #{ri_id}, to vpc #{instances[instance_id][:vpc]}")
              end
              summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] -= 1
              summary[ri[:type]][instances[instance_id][:az]][ri[:platform]][instances[instance_id][:vpc]][ri[:tenancy]][1] += 1
              reserved_instances[ri_id][:count] -= 1
              reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
              recommendations << recommendation
              return true
            end
          end
        end
      end
    end

    # Now I look for type changes
    reserved_instances.each do |ri_id, ri|
      if !ri.nil? && ri[:type].split(".")[0] == family && ri[:az][0..-2] == region && ri[:platform] == platform && ri[:tenancy] == tenancy
        # This reserved instance is of the usable type
        if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] > summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][0]
          # If for this reservation type we have excess of RIs
          # I'm going to look for an instance which can use this reservation
          excess_instance.each do |instance_id|
            if instances[instance_id][:type] != ri[:type] 
              factor_instance = get_factor(instances[instance_id][:type])
              factor_ri = get_factor(ri[:type])
              recommendation = {rid: ri_id}
              recommendation[:type] = instances[instance_id][:type]
              recommendation[:az] = instances[instance_id][:az] if instances[instance_id][:az] != ri[:az]
              recommendation[:vpc] = instances[instance_id][:vpc] if instances[instance_id][:vpc] != ri[:vpc]
              if factor_ri > factor_instance
                # Split the RI
                new_instances = factor_ri / factor_instance
                recommendation[:count] = new_instances.to_i
                #Rails.logger.debug("Change in the RI #{ri_id}, split in #{new_instances} to type #{instances[instance_id][:type]}")

                summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] -= 1
                summary[instances[instance_id][:type]][instances[instance_id][:az]][ri[:platform]][instances[instance_id][:vpc]][ri[:tenancy]][1] += new_instances
                reserved_instances[ri_id][:count] -= 1
                reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
                recommendations << recommendation
                return true
              else
                ri_needed = factor_instance / factor_ri
                if (summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1]-ri_needed) >= summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][0]
                  # If after the RI modification I'm going to have enough RIs
                  #Rails.logger.debug("Change in the RI #{ri_id}, join in #{ri_needed} to type #{instances[instance_id][:type]}")
                  recommendation[:count] = 1
                  summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] -= ri_needed
                  summary[instances[instance_id][:type]][instances[instance_id][:az]][ri[:platform]][instances[instance_id][:vpc]][ri[:tenancy]][1] += 1
                  reserved_instances[ri_id][:count] -= ri_needed
                  reserved_instances[ri_id] = nil if reserved_instances[ri_id][:count] == 0
                  recommendations << recommendation
                  return true
                end
              end
            end
          end
        end
      end
    end

    return false

  end

  def calculate_excess(summary, excess)
    summary.each do |type, elem1|
      elem1.each do |az, elem2| 
        elem2.each do |platform, elem3| 
          elem3.each do |vpc, elem4| 
            elem4.each do |tenancy, total|
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
  end

  def get_factor(type)
    size = type.split(".")[1]
    return case size
    when "micro"
      0.5
    when "small"
      1
    when "medium"
      2
    when "large"
      4
    when "xlarge"
      8
    when "2xlarge"
      16
    when "4xlarge"
      32
    when "8xlarge"
      64
    when "10xlarge"
      80
    else
      0
    end
  end

  def get_summary(instances, reserved_instances)
    summary = {}

    instances.each do |instance_id, instance|
      summary[instance[:type]] = {} if summary[instance[:type]].nil?
      summary[instance[:type]][instance[:az]] = {} if summary[instance[:type]][instance[:az]].nil?
      summary[instance[:type]][instance[:az]][instance[:platform]] = {} if summary[instance[:type]][instance[:az]][instance[:platform]].nil?
      summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]] = {} if summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]].nil?
      summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]][instance[:tenancy]] = [0,0] if summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]][instance[:tenancy]].nil?
      summary[instance[:type]][instance[:az]][instance[:platform]][instance[:vpc]][instance[:tenancy]][0] += 1
    end

    reserved_instances.each do |ri_id, ri|
      summary[ri[:type]] = {} if summary[ri[:type]].nil?
      summary[ri[:type]][ri[:az]] = {} if summary[ri[:type]][ri[:az]].nil?
      summary[ri[:type]][ri[:az]][ri[:platform]] = {} if summary[ri[:type]][ri[:az]][ri[:platform]].nil?
      summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]] = {} if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]].nil?
      summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]] = [0,0] if summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]].nil?
      summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] += ri[:count]
    end

    return summary
  end
end
