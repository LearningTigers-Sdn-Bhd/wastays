# frozen_string_literal: true

module StayView
  RoomTypeRecord = Data.define(
    :id, :name, :room_numbers, :smoking_allowed, :pets_allowed,
    :base_price, :master_rate_plan_id, :rate_currency
  ) do
    def initialize(id:, name:, room_numbers:, smoking_allowed:, pets_allowed:, base_price: nil, master_rate_plan_id: nil, rate_currency: nil)
      super(
        id: id,
        name: name.to_s.freeze,
        room_numbers: Immutable.array(Array(room_numbers).flatten.compact.map(&:to_s).reject(&:blank?)),
        smoking_allowed: smoking_allowed,
        pets_allowed: pets_allowed,
        base_price: base_price&.to_d,
        master_rate_plan_id: master_rate_plan_id,
        rate_currency: rate_currency&.to_s&.freeze
      )
    end
  end

  BookingRecord = Data.define(
    :booking_room_id, :booking_id, :room_type_id, :room_number, :status, :guest_name, :primary_guest_name, :check_in, :check_out,
    :group_booking_id, :group_reference, :group_name, :group_position
  ) do
    def initialize(**attributes)
      %i[group_booking_id group_reference group_name group_position].each { |key| attributes[key] ||= nil }
      attributes[:primary_guest_name] ||= attributes[:guest_name]
      attributes[:room_number] = attributes.fetch(:room_number).to_s.freeze
      attributes[:status] = attributes.fetch(:status).to_sym
      %i[guest_name primary_guest_name group_reference group_name].each do |key|
        attributes[key] = attributes[key]&.to_s&.freeze
      end
      super(**attributes)
    end
  end
  GroupRoomRecord = Data.define(:group_booking_id, :booking_id, :booking_room_id, :group_position, :room_number, :room_type_name) do
    def initialize(**attributes)
      %i[room_number room_type_name].each { |key| attributes[key] = attributes.fetch(key).to_s.freeze }
      super(**attributes)
    end
  end
  RoomStatusRecord = Data.define(:room_type_id, :room_number, :status, :priority, :dnd, :dnd_date)
  RoomBlockRecord = Data.define(:id, :room_type_id, :room_number, :block_type, :reason, :start_date, :end_date)
  HousekeepingAlertRecord = Data.define(
    :request_id, :room_type_id, :room_number, :details, :status, :requested_at, :assigned_to_id, :assigned_to_name
  ) do
    def initialize(**attributes)
      attributes[:room_number] = attributes.fetch(:room_number).to_s.freeze
      attributes[:details] = attributes.fetch(:details).to_s.freeze
      attributes[:status] = attributes.fetch(:status).to_sym
      attributes[:assigned_to_name] = attributes[:assigned_to_name].presence&.to_s&.freeze
      super(**attributes)
    end
  end

  RoomInventoryRecord = Data.define(:room_type_id, :date, :quantity, :status, :available_room_numbers) do
    def initialize(room_type_id:, date:, quantity:, status:, available_room_numbers: [])
      super(
        room_type_id:,
        date: date.to_date,
        quantity: Integer(quantity),
        status: status.to_sym,
        available_room_numbers: Immutable.array(
          Array(available_room_numbers).flatten.compact.map(&:to_s).reject(&:blank?)
        )
      )
    end
  end

  StandardRateRecord = Data.define(:room_type_id, :rate_plan_id, :date, :price, :currency) do
    def initialize(room_type_id:, rate_plan_id:, date:, price:, currency:)
      super(
        room_type_id:,
        rate_plan_id:,
        date: date.to_date,
        price: price.to_d,
        currency: currency.to_s.freeze
      )
    end
  end

  Inventory = Data.define(
    :room_types, :bookings, :group_rooms, :room_statuses, :room_blocks,
    :housekeeping_alerts, :room_inventories, :standard_rates, :financial_signals
  ) do
    def initialize(
      room_types:, bookings:, group_rooms:, room_statuses:, room_blocks:, housekeeping_alerts: [], room_inventories: [],
      standard_rates: [], financial_signals: {}
    )
      super(
        room_types: Immutable.array(room_types),
        bookings: Immutable.array(bookings),
        group_rooms: Immutable.hash(group_rooms),
        room_statuses: Immutable.array(room_statuses),
        room_blocks: Immutable.array(room_blocks),
        housekeeping_alerts: Immutable.array(housekeeping_alerts),
        room_inventories: Immutable.array(room_inventories),
        standard_rates: Immutable.array(standard_rates),
        financial_signals: Immutable.hash(financial_signals)
      )
    end
  end
end
