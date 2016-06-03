class CreateModifications < ActiveRecord::Migration
  def change
    create_table :modifications do |t|
      t.string :modificationid
      t.string :status

      t.timestamps null: false
    end
  end
end
