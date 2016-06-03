class AddOfferingToReservedInstance < ActiveRecord::Migration
  def change
    add_column :reserved_instances, :offering, :string
    add_column :reserved_instances, :duration, :integer
  end
end
