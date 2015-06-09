class Setup < ActiveRecord::Base
  def self.get_regions
    regions = {"eu-west-1"=> false, "us-east-1"=> false, "eu-central-1"=> false, "us-west-1"=> false, "us-west-2"=> false, "ap-southeast-1"=> false, "ap-southeast-2"=> false, "ap-northeast-1"=> false, "sa-east-1"=> false}
    setup = Setup.first
    if !setup.nil?
      regions_text = setup.regions
      regions_list = regions_text.split ","
      regions_list.each do |region|
        regions[region] = true if !regions[region].nil?
      end
    end
    return regions
  end

  def self.put_regions(regions)
    regions_list = []
    regions.each do |region, value|
      regions_list << region if value
    end
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.regions = regions_list.join ","
    setup.save
  end
end
