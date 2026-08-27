# frozen_string_literal: true

module StayView
  # Display sections for the rooms view. The board itself stays grouped by room
  # type, because the inventory summaries belong to a room type. This service
  # only decides how the finished rooms are laid out on the screen.
  class BuildRoomSections
    MODES = %w[none room_type room_group].freeze
    DEFAULT_MODE = "room_type"

    Item = Data.define(:room, :inventory_summary)

    Section = Data.define(:key, :label, :room_type_id, :room_group_id, :items) do
      def initialize(key:, label:, items:, room_type_id: nil, room_group_id: nil)
        super(key: key.to_s.freeze, label: label.to_s.freeze, room_type_id:, room_group_id:,
              items: Immutable.array(items))
      end

      def size = items.size
    end

    def self.call(...) = new(...).call

    def initialize(board:, mode:, date:)
      @board = board
      @mode = MODES.include?(mode.to_s) ? mode.to_s : DEFAULT_MODE
      @date = date
    end

    def call
      case mode
      when "room_group" then room_group_sections
      when "none" then flat_sections
      else room_type_sections
      end
    end

    private

    attr_reader :board, :mode, :date

    def items
      @items ||= board.room_groups.flat_map do |room_type_group|
        summary = room_type_group.inventory_summary_for(date)
        room_type_group.rooms.map { |room| Item.new(room:, inventory_summary: summary) }
      end
    end

    def flat_sections
      return EMPTY if items.empty?

      [ Section.new(key: "all", label: "All rooms", items: items) ].freeze
    end

    def room_type_sections
      board.room_groups.filter_map do |room_type_group|
        next if room_type_group.rooms.empty?

        summary = room_type_group.inventory_summary_for(date)
        Section.new(
          key: "room_type-#{room_type_group.room_type_id}",
          label: room_type_group.name,
          room_type_id: room_type_group.room_type_id,
          items: room_type_group.rooms.map { |room| Item.new(room:, inventory_summary: summary) }
        )
      end.freeze
    end

    # One section for each room group, in name order, with the rooms that belong
    # to no group last. A group can hold rooms of several room types, so each
    # item keeps the inventory summary of its own room type.
    def room_group_sections
      grouped = items.group_by { |item| item.room.room_group_id }
      ungrouped = grouped.delete(nil)

      sections = grouped
        .map do |room_group_id, group_items|
          Section.new(
            key: "room_group-#{room_group_id}",
            label: group_items.first.room.room_group_name,
            room_group_id:,
            items: group_items
          )
        end
        .sort_by { |section| [ section.label.downcase, section.room_group_id ] }

      if ungrouped.present?
        sections << Section.new(
          key: "room_group-ungrouped",
          label: ::Rooms::GroupAssignmentsQuery::UNGROUPED_LABEL,
          items: ungrouped
        )
      end

      sections.freeze
    end

    EMPTY = [].freeze
  end
end
