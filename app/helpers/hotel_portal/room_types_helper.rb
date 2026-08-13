# frozen_string_literal: true

module HotelPortal::RoomTypesHelper
  def room_group_tab_class(active_group_id, tab_group_id)
    is_active = if tab_group_id == :all
                  active_group_id.blank?
    elsif tab_group_id == :unassigned
                  active_group_id == "unassigned"
    else
                  active_group_id == tab_group_id.to_s
    end

    if is_active
      "group inline-flex h-9 items-center gap-2 whitespace-nowrap rounded-lg px-4 text-sm font-semibold bg-blue-600 text-primary-foreground transition-all duration-150"
    else
      "group inline-flex h-9 items-center gap-2 whitespace-nowrap rounded-lg px-4 text-sm font-medium text-muted-foreground transition-all duration-150 hover:bg-muted hover:text-foreground"
    end
  end

  def unassigned_room_types_count(hotel)
    hotel.room_types.unassigned.count
  end

  def room_type_amenities_json(room_type)
    (room_type.amenities || []).to_json
  end

  def all_room_amenities_json
    Hotel::ROOM_AMENITIES.to_json
  end

  def categorized_room_amenities
    Hotel::CATEGORIZED_ROOM_AMENITIES
  end
end
