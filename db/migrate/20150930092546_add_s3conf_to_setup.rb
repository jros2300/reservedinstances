class AddS3confToSetup < ActiveRecord::Migration
  def change
    add_column :setups, :importdbr, :boolean
    add_column :setups, :s3bucket, :string
  end
end
