class SummaryController < ApplicationController
  include AwsCommon
  def index
    @summary = get_summary
  end

  def recommendations
    summary = get_summary
  end


  private

  def get_summary
    instances = get_instances(Setup.get_regions, get_account_ids)
    reserved_instances = get_reserved_instances(Setup.get_regions, get_account_ids)
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
      summary[ri[:type]][ri[:az]][ri[:platform]][ri[:vpc]][ri[:tenancy]][1] += 1
    end

    return summary
  end
end
