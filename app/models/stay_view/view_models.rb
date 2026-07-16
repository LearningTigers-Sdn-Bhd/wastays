# frozen_string_literal: true

module StayView
  ViewModels = true

  TrackRange = Data.define(:start_track, :end_track, :clipped_left, :clipped_right) do
    alias_method :clipped_left?, :clipped_left
    alias_method :clipped_right?, :clipped_right
  end

  Occupancy = Data.define(:state, :booking_id, :booking_status, :label) do
    def initialize(state:, booking_id: nil, booking_status: nil, label: nil)
      super(state: state.to_sym, booking_id: booking_id, booking_status: booking_status&.to_sym, label: label&.to_s&.freeze)
    end
  end

  DayCell = Data.define(:date, :occupancies, :operational_kinds) do
    def initialize(date:, occupancies:, operational_kinds: [])
      super(date: date.to_date, occupancies: Immutable.array(occupancies), operational_kinds: Immutable.array(operational_kinds.map(&:to_sym)))
    end
  end

  GroupRoomSummary = Data.define(:booking_id, :booking_room_id, :group_position, :room_number, :room_type_name) do
    def initialize(**attributes)
      %i[room_number room_type_name].each { |key| attributes[key] = attributes.fetch(key).to_s.freeze }
      super(**attributes)
    end
  end

  BookingSegment = Data.define(
    :dom_id, :booking_id, :booking_room_id, :guest_label, :primary_guest_name, :booking_type, :status, :check_in, :check_out,
    :start_track, :end_track, :clipped_left, :clipped_right, :accessible_label, :capabilities,
    :group_booking_id, :group_reference, :group_name, :group_position, :group_rooms
  ) do
    alias_method :clipped_left?, :clipped_left
    alias_method :clipped_right?, :clipped_right

    def initialize(**attributes)
      %i[group_booking_id group_reference group_name group_position].each { |key| attributes[key] ||= nil }
      attributes[:primary_guest_name] ||= attributes[:guest_label]
      attributes[:booking_type] ||= attributes[:group_booking_id].present? ? :group : :single
      attributes[:group_rooms] ||= []
      attributes[:booking_type] = attributes.fetch(:booking_type).to_sym
      attributes[:status] = attributes.fetch(:status).to_sym
      %i[dom_id guest_label primary_guest_name accessible_label].each { |key| attributes[key] = attributes.fetch(key).to_s.freeze }
      %i[group_reference group_name].each { |key| attributes[key] = attributes[key]&.to_s&.freeze }
      attributes[:group_rooms] = Immutable.array(attributes.fetch(:group_rooms, []))
      super(**attributes)
    end
  end

  OperationalSegment = Data.define(
    :dom_id, :room_block_id, :kind, :label, :start_date, :end_date, :start_track, :end_track,
    :clipped_left, :clipped_right, :accessible_label, :capabilities
  ) do
    alias_method :clipped_left?, :clipped_left
    alias_method :clipped_right?, :clipped_right

    def initialize(**attributes)
      attributes[:room_block_id] ||= nil
      attributes[:kind] = attributes.fetch(:kind).to_sym
      %i[dom_id label accessible_label].each { |key| attributes[key] = attributes.fetch(key).to_s.freeze }
      super(**attributes)
    end
  end

  HousekeepingAlert = Data.define(
    :request_id, :room_key, :details, :status, :requested_at, :assigned_to_id, :assigned_to_name, :capabilities
  ) do
    def initialize(**attributes)
      attributes[:room_key] = attributes.fetch(:room_key).to_s.freeze
      attributes[:details] = attributes.fetch(:details).to_s.freeze
      attributes[:status] = attributes.fetch(:status).to_sym
      attributes[:assigned_to_name] = attributes[:assigned_to_name].presence&.to_s&.freeze
      super(**attributes)
    end
  end

  RoomRow = Data.define(
    :key, :dom_id, :room_number, :room_type_id, :room_type_name, :smoking_allowed, :pets_allowed,
    :current_physical_status, :operational_flags, :day_cells, :booking_segments,
    :operational_segments, :housekeeping_alerts, :capabilities
  ) do
    def initialize(**attributes)
      %i[key dom_id room_number room_type_name].each { |key| attributes[key] = attributes.fetch(key).to_s.freeze }
      attributes[:current_physical_status] = attributes[:current_physical_status]&.to_sym
      attributes[:operational_flags] = Immutable.hash(attributes.fetch(:operational_flags))
      attributes[:housekeeping_alerts] ||= []
      %i[day_cells booking_segments operational_segments housekeeping_alerts].each do |key|
        attributes[key] = Immutable.array(attributes.fetch(key))
      end
      super(**attributes)
    end

    def occupancy_for(date)
      day_cells.find { |cell| cell.date == date.to_date }&.occupancies || EMPTY_OCCUPANCIES
    end

    EMPTY_OCCUPANCIES = [].freeze
  end

  RoomGroup = Data.define(:room_type_id, :name, :rooms) do
    def initialize(room_type_id:, name:, rooms:)
      super(room_type_id: room_type_id, name: name.to_s.freeze, rooms: Immutable.array(rooms))
    end
  end

  RoomTypeOption = Data.define(:id, :name) do
    def initialize(id:, name:)
      super(id:, name: name.to_s.freeze)
    end
  end

  FilterState = Data.define(:room_type_id, :booking_status, :occupancy, :physical_status) do
    def self.build(value = {})
      source = value.to_h.symbolize_keys
      new(
        room_type_id: Integer(source[:room_type_id], exception: false),
        booking_status: normalize_symbol(source[:booking_status], Booking::OCCUPYING_STATUSES),
        occupancy: normalize_symbol(source[:occupancy], %w[available arrival occupied departure]),
        physical_status: normalize_symbol(source[:physical_status], RoomStatus::STATUSES - [ "late_checkout_detected" ])
      )
    end

    def self.normalize_symbol(value, allowed)
      candidate = value.to_s
      allowed.include?(candidate) ? candidate.to_sym : nil
    end

    private_class_method :normalize_symbol
  end

  StatusCounts = Data.define(:rooms, :physical_statuses, :occupancies, :booking_statuses, :operational_segments) do
    def initialize(rooms:, physical_statuses:, occupancies:, booking_statuses:, operational_segments:)
      super(
        rooms: rooms,
        physical_statuses: Immutable.hash(physical_statuses),
        occupancies: Immutable.hash(occupancies),
        booking_statuses: Immutable.hash(booking_statuses),
        operational_segments: Immutable.hash(operational_segments)
      )
    end
  end

  Capabilities = Data.define(
    :view_board, :view_booking, :create_booking, :move_booking, :change_dates, :reassign_room,
    :check_in, :check_out, :view_rates, :view_financial_status, :view_room_readiness,
    :manage_room_status, :manage_housekeeping, :update_housekeeping_status, :manage_room_blocks
  ) do
    members.each { |name| alias_method "#{name}?", name }
  end

  Board = Data.define(:view_mode, :date_window, :room_groups, :room_type_options, :status_counts, :filters, :capabilities) do
    def initialize(view_mode:, date_window:, room_groups:, room_type_options:, status_counts:, filters:, capabilities:)
      super(
        view_mode: view_mode.to_sym,
        date_window: date_window,
        room_groups: Immutable.array(room_groups),
        room_type_options: Immutable.array(room_type_options),
        status_counts: status_counts,
        filters: filters,
        capabilities: capabilities
      )
    end

    def empty?
      room_groups.all? { |group| group.rooms.empty? }
    end
  end
end
