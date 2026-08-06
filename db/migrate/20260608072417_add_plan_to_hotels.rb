class AddPlanToHotels < ActiveRecord::Migration[8.0]
  def change
    add_reference :hotels, :plan, null: true, foreign_key: true
  end
end
