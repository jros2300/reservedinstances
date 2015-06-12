class AddNextToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :nextrun, :datetime
  end
end
