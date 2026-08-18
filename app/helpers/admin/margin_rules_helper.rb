# frozen_string_literal: true

module Admin
  module MarginRulesHelper
    def margin_rule_target_info(rule, hotels = [])
      if rule.settable_type.blank?
        [ "Global Default", "Applied when no hotel or room override exists", "text-blue-700" ]
      elsif rule.settable_type == "Hotel"
        hotel_name = rule.settable&.name || Array(hotels).find { |h| h.id == rule.settable_id }&.name
        [ "Hotel Override", hotel_name.presence || "Applies to hotel ##{rule.settable_id}", "text-foreground" ]
      else
        room_type_name = if rule.settable.respond_to?(:name)
          "#{rule.settable.name} (#{rule.settable.hotel&.name})"
        else
          "Applies to room type ##{rule.settable_id}"
        end
        [ "Room Type Override", room_type_name, "text-foreground" ]
      end
    end

    def room_type_select_options(room_types)
      Array(room_types).map { |rt| [ "#{rt.name} (#{rt.hotel&.name})", rt.id ] }
    end
  end
end
