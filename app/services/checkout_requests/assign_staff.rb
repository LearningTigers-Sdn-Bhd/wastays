# frozen_string_literal: true

module CheckoutRequests
  class AssignStaff
    def initialize(hotel:, checkout_request:, assigned_to_id:, current_user:)
      @hotel = hotel
      @checkout_request = checkout_request
      @assigned_to_id = assigned_to_id.presence
      @current_user = current_user
    end

    def call
      HousekeepingTasks::AssignStaff.new(
        hotel: @hotel,
        checkout_request: @checkout_request,
        assigned_to_id: @assigned_to_id,
        current_user: @current_user
      ).call
    end
  end
end
