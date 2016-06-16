class CreateRecommendationCaches < ActiveRecord::Migration
  def change
    create_table :recommendation_caches do |t|
      t.text :object

      t.timestamps null: false
    end
  end
end
