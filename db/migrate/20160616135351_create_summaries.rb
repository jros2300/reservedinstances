class CreateSummaries < ActiveRecord::Migration
  def change
    create_table :summaries do |t|
      t.string :instancetype
      t.string :az
      t.string :tenancy
      t.string :platform
      t.integer :total
      t.integer :reservations

      t.timestamps null: false
    end
  end
end
