class AddMinutesToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :minutes, :integer
  end
end
