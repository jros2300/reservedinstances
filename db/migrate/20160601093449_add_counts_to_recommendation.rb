class AddCountsToRecommendation < ActiveRecord::Migration
  def change
    add_column :recommendations, :counts, :string
  end
end
