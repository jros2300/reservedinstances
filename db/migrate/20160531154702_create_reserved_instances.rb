class CreateReservedInstances < ActiveRecord::Migration
  def change
    create_table :reserved_instances do |t|
      t.string :accountid
      t.string :reservationid
      t.string :instancetype
      t.string :az
      t.string :tenancy
      t.string :platform
      t.string :network
      t.integer :count
      t.datetime :enddate
      t.string :status
      t.string :rolearn

      t.timestamps null: false
    end
  end
end
