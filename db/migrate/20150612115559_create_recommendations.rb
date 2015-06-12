class CreateRecommendations < ActiveRecord::Migration
  def change
    create_table :recommendations do |t|
      t.string :rid
      t.string :az
      t.string :instancetype
      t.string :vpc
      t.integer :count
      t.datetime :timestamp
      t.string :accountid

      t.timestamps null: false
    end
  end
end
