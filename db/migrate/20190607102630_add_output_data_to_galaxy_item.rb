class AddOutputDataToGalaxyItem < ActiveRecord::Migration[5.2]
  def change
    add_column :galaxy_execution_queue_items, :output_data, :text
  end
end
