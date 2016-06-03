class AddAffinityToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :affinity, :boolean
  end
end
