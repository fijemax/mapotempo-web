class AlterCustomerAddOptimizationMaxSplitSize < ActiveRecord::Migration
  def change
    add_column :customers, :optimization_max_split_size, :integer
  end
end
