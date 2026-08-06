# frozen_string_literal: true

module StayView
  class BuildCapabilities
    def self.call(user:, hotel:)
      new(user:, hotel:).call
    end

    def initialize(user:, hotel:)
      @user = user
      @hotel = hotel
    end

    def call
      return all_capabilities if user.superadmin?

      permission_slugs = user.user_hotel_accesses.active
        .joins(role: :permissions)
        .where(hotel_id: hotel.id)
        .pluck("permissions.slug")
        .to_set

      view_bookings = permission_slugs.include?("view_bookings")
      view_financial_status = view_bookings && permission_slugs.include?("view_financial_status")
      manage_bookings = permission_slugs.include?("manage_bookings")
      manage_arrivals = permission_slugs.include?("manage_guest_arrival")
      manage_room_status = permission_slugs.include?("manage_room_status")
      view_readiness = manage_room_status || permission_slugs.include?("view_room_readiness")
      housekeeping_enabled = hotel.feature_enabled?("task_assignment_minibar_log")

      Capabilities.new(
        view_board: view_bookings || manage_bookings || view_readiness,
        view_booking: view_bookings,
        manage_bookings: manage_bookings,
        create_booking: manage_bookings,
        move_booking: manage_bookings,
        change_dates: manage_bookings,
        reassign_room: manage_bookings,
        check_in: manage_arrivals,
        check_out: manage_arrivals,
        view_rates: permission_slugs.include?("manage_rates"),
        view_financial_status:,
        view_room_readiness: view_readiness,
        manage_room_status: manage_room_status,
        manage_housekeeping: housekeeping_enabled && permission_slugs.include?("dispatch_housekeeping_tasks"),
        take_housekeeping_task: housekeeping_enabled && permission_slugs.include?("perform_housekeeping_tasks"),
        update_housekeeping_status: housekeeping_enabled && permission_slugs.include?("manage_requests"),
        manage_room_blocks: manage_room_status
      )
    end

    private

    attr_reader :user, :hotel

    def all_capabilities
      attributes = Capabilities.members.index_with { true }
      Capabilities.new(**attributes)
    end
  end
end
