class RouterWrapperPublicTransport < ActiveRecord::Base ; end

class AlterTableRouterDimensions < ActiveRecord::Migration
  def up
    add_column :routers, :time, :boolean, null: false, default: true
    add_column :routers, :distance, :boolean, null: false, default: false
    Router.where(type: 'RouterWrapperPublicTransport').update_all type: "RouterWrapper"
  end

  def down
    remove_column :routers, :time
    remove_column :routers, :distance
  end
end
