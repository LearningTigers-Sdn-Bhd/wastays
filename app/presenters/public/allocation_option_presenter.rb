# frozen_string_literal: true

module Public
  class AllocationOptionPresenter < SimpleDelegator
    def initialize(allocation_option, view_context)
      @allocation_option = allocation_option
      @view_context = view_context
      super(allocation_option)
    end

    def display_total_price(display_currency, hotel)
      @view_context.display_amount(total_price,
                                   quote_currency: currency,
                                   display_currency: display_currency,
                                   hotel: hotel)
    end

    def rooms_summary
      rooms.group_by { |allocated_room| allocated_room.room_type.name }
           .map { |name, group| "#{group.sum(&:quantity)}x #{name}" }
           .join(", ")
    end

    def allocations_params
      rooms.map do |allocated_room|
        { room_type_id: allocated_room.room_type.id, quantity: allocated_room.quantity }
      end
    end
  end
end
