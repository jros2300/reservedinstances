class AddPasswordToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :password, :string
  end
end
