class AddProcessedToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :processed, :datetime
  end
end
