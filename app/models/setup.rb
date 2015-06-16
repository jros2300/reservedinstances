class Setup < ActiveRecord::Base
  require 'bcrypt'

  def self.get_minutes
    minutes = 0
    setup = Setup.first
    if !setup.nil?
      minutes = setup.minutes if !setup.minutes.nil?
    end
    return minutes
  end

  def self.put_minutes(minutes)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.minutes = minutes
    setup.save
    update_next
  end

  def self.get_password
    password = BCrypt::Password.create(ENV['DEFAULT_PASSWORD'])
    setup = Setup.first
    if !setup.nil? && !setup.password.nil?
      password = setup.password
    end
    return password
  end

  def self.put_password(password)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.password = BCrypt::Password.create(password)
    setup.save
  end

  def self.test_password(password)
    return BCrypt::Password.new(get_password).is_password? password
  end

  def self.update_next
    minutes = 0
    setup = Setup.first
    if !setup.nil?
      minutes = setup.minutes if !setup.minutes.nil?
    end

    if minutes > 0
      setup.nextrun = Time.current + minutes.minutes
      setup.save
    end
  end

  def self.now_after_next
    after_next = false
    setup = Setup.first
    if !setup.nil? && !setup.nextrun.nil?
      after_next = (setup.nextrun < Time.current)
    end
    return after_next
  end

  def self.get_regions
    regions = {"eu-west-1"=> false, "us-east-1"=> false, "eu-central-1"=> false, "us-west-1"=> false, "us-west-2"=> false, "ap-southeast-1"=> false, "ap-southeast-2"=> false, "ap-northeast-1"=> false, "sa-east-1"=> false}
    setup = Setup.first
    if !setup.nil? && !setup.regions.nil?
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
