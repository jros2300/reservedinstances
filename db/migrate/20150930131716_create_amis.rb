class CreateAmis < ActiveRecord::Migration
  def change
    create_table :amis do |t|
      t.string :ami
      t.string :operation
    end
  end
end
