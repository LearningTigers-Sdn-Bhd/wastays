# frozen_string_literal: true

module StayView
  class CalculateInventorySummaries
    SOLD_STATES = %i[arrival occupied].freeze

    def self.call(room_groups:, room_inventories:, dates:)
      inventories_by_key = room_inventories.index_by { |record| [ record.room_type_id, record.date ] }

      room_groups.map do |group|
        summaries = dates.map do |date|
          calculate_date(group:, date: date.to_date, inventory: inventories_by_key[[ group.room_type_id, date.to_date ]])
        end
        group.with(inventory_summaries: Immutable.array(summaries))
      end.freeze
    end

    def self.calculate_date(group:, date:, inventory:)
      sold_rooms = group.rooms.select { |room| sold_on?(room, date) }
      unblocked_rooms = group.rooms.reject { |room| blocked_on?(room, date) }
      candidates = unblocked_rooms.reject { |room| sold_rooms.include?(room) }
      available = available_count(candidates:, inventory:)
      sellable = [ unblocked_rooms.size, sold_rooms.size + available ].min

      InventoryDateSummary.new(
        date:,
        sellable:,
        sold: sold_rooms.size,
        available:,
        occupancy: sellable.zero? ? nil : sold_rooms.size.fdiv(sellable)
      )
    end

    def self.available_count(candidates:, inventory:)
      return candidates.size unless inventory
      return 0 if inventory.status == :closed

      limits = [ candidates.size, inventory.quantity ]
      if inventory.available_room_numbers.any?
        named_rooms = inventory.available_room_numbers.to_set
        limits << candidates.count { |room| named_rooms.include?(room.room_number) }
      end
      limits.min
    end

    def self.sold_on?(room, date)
      room.occupancy_for(date).any? { |occupancy| SOLD_STATES.include?(occupancy.state) }
    end

    def self.blocked_on?(room, date)
      room.operational_segments.any? do |segment|
        segment.room_block_id.present? && segment.start_date <= date && date < segment.end_date
      end
    end

    private_class_method :calculate_date, :available_count, :sold_on?, :blocked_on?
  end
end
