class CreateInstances < ActiveRecord::Migration
  def change
    create_table :instances do |t|
      t.string :accountid
      t.string :instanceid
      t.string :instancetype
      t.string :az
      t.string :tenancy
      t.string :platform
      t.string :network

      t.timestamps null: false
    end
  end
end
