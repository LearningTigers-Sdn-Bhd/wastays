class UpdateRatePlansToBelongToHotel < ActiveRecord::Migration[8.0]
  def change
    rate_plan_hotel_mappings = {}
    if column_exists?(:rate_plans, :room_type_id)
      select_all("SELECT id, room_type_id FROM rate_plans").each do |row|
        rate_plan_id = row['id']
        room_type_id = row['room_type_id']
        if room_type_id
          res = select_one("SELECT hotel_id FROM room_types WHERE id = #{room_type_id}")
          rate_plan_hotel_mappings[rate_plan_id] = res['hotel_id'] if res
        end
      end
    end

    if column_exists?(:rate_plans, :room_type_id)
      if foreign_key_exists?(:rate_plans, :room_types)
        remove_foreign_key :rate_plans, :room_types
      end
      remove_column :rate_plans, :room_type_id, :bigint
    end

    unless column_exists?(:rate_plans, :hotel_id)
      add_reference :rate_plans, :hotel, null: true, foreign_key: true
    end

    rate_plan_hotel_mappings.each do |rate_plan_id, hotel_id|
      execute("UPDATE rate_plans SET hotel_id = #{hotel_id} WHERE id = #{rate_plan_id}")
    end

    first_hotel = select_one("SELECT id FROM hotels ORDER BY id LIMIT 1")
    if first_hotel
      execute("UPDATE rate_plans SET hotel_id = #{first_hotel['id']} WHERE hotel_id IS NULL")
    end

    change_column_null :rate_plans, :hotel_id, false

    unless column_exists?(:rate_plans, :description)
      add_column :rate_plans, :description, :text
    end
  end
end
