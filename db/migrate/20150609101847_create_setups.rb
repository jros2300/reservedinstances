class CreateSetups < ActiveRecord::Migration
  def change
    create_table :setups do |t|
      t.text :regions

      t.timestamps null: false
    end
  end
end
