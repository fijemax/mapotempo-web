class AlterTableRoutesLockVersion < ActiveRecord::Migration
  def up
    add_column :routes, :lock_version, :integer, default: 0, null: false
  end

  def down
    remove_column :routes, :lock_version
  end
end
