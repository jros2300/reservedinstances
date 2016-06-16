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

  def self.get_minutesrefresh
    minutesrefresh = 5
    setup = Setup.first
    if !setup.nil?
      minutesrefresh = setup.minutesrefresh if !setup.minutesrefresh.nil?
    end
    return minutesrefresh
  end

  def self.put_minutesrefresh(minutes)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.minutesrefresh = minutes
    setup.save
    update_nextrefresh
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

  def self.get_affinity
    setup = Setup.first
    affinity = false
    if !setup.nil? && !setup.affinity.nil?
      affinity = setup.affinity
    end
    return affinity
  end

  def self.put_affinity(affinity)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.affinity = affinity
    setup.save
  end
  
  def self.get_importdbr
    setup = Setup.first
    importdbr = false
    if !setup.nil? && !setup.importdbr.nil?
      importdbr = setup.importdbr
    end
    return importdbr
  end

  def self.put_importdbr(importdbr)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.importdbr = importdbr
    setup.save
  end

  def self.get_s3bucket
    setup = Setup.first
    s3bucket = ''
    if !setup.nil? && !setup.s3bucket.nil?
      s3bucket = setup.s3bucket
    end
    return s3bucket
  end

  def self.put_s3bucket(s3bucket)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.s3bucket = s3bucket
    setup.save
  end

  def self.get_processed
    setup = Setup.first
    s3bucket = ''
    if !setup.nil? && !setup.processed.nil?
      processed = setup.processed
    end
    return processed
  end

  def self.put_processed(processed)
    setup = Setup.first
    setup = Setup.new if setup.nil?

    setup.processed = processed
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
      return false if setup.minutes.nil? || setup.minutes==0
      after_next = (setup.nextrun < Time.current)
    end
    return after_next
  end

  def self.update_nextrefresh
    minutesrefresh = 5
    setup = Setup.first
    if !setup.nil?
      minutesrefresh = setup.minutesrefresh if !setup.minutesrefresh.nil?
    end

    setup.nextrefresh = Time.current + minutesrefresh.minutes
    setup.save
  end

  def self.now_after_nextrefresh
    ###### DELETE THIS #######
    return true
    ###### DELETE THIS #######
    after_nextrefresh = true
    setup = Setup.first
    if !setup.nil? && !setup.nextrefresh.nil?
      after_nextrefresh = (setup.nextrefresh < Time.current)
    end
    return after_nextrefresh
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
