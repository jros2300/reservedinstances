class AddRefreshToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :nextrefresh, :datetime
    add_column :setups, :minutesrefresh, :integer
  end
end
