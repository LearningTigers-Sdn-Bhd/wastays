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
      staff = find_staff if @assigned_to_id
      metadata = @checkout_request.metadata.to_h

      if staff
        if metadata["assigned_to"] != staff.id
          history = Array(metadata["assignment_history"])
          history << {
            "assigned_to_id" => staff.id,
            "assigned_to_name" => staff.name,
            "assigned_by_id" => @current_user.id,
            "assigned_by_name" => @current_user.name,
            "timestamp" => Time.current.iso8601
          }
          metadata["assignment_history"] = history
        end
        metadata["assigned_to"] = staff.id
        metadata["assigned_to_name"] = staff.name
        metadata["workflow_status"] = "assigned"
        @checkout_request.status = "assigned" if @checkout_request.status.in?(%w[new pending acknowledged])
      else
        if metadata["assigned_to"].present?
          history = Array(metadata["assignment_history"])
          history << {
            "assigned_to_name" => "Unassigned",
            "assigned_by_id" => @current_user.id,
            "assigned_by_name" => @current_user.name,
            "timestamp" => Time.current.iso8601
          }
          metadata["assignment_history"] = history
        end
        metadata.delete("assigned_to")
        metadata.delete("assigned_to_name")
        metadata["workflow_status"] = "new"
        @checkout_request.status = "new" if @checkout_request.status.in?(%w[assigned in_progress acknowledged])
      end

      @checkout_request.update!(metadata: metadata)
    end

    private

    def find_staff
      User.where(id: UserHotelAccess.active
                                     .where(hotel_id: @hotel.id)
                                     .joins(:role)
                                     .where(roles: { slug: "housekeeper" })
                                     .select(:user_id))
          .find_by(id: @assigned_to_id)
    end
  end
end
