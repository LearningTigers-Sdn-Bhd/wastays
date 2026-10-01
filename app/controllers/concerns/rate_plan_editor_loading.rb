# frozen_string_literal: true

# Loads the selected attached-room context for the rate plan page and the
# responses its writes share.
module RatePlanEditorLoading
  extend ActiveSupport::Concern

  included do
    include SheetActionCompletion
  end

  private

  def load_rate_plan_editor(room_type_id: nil)
    @assignments = @rate_plan.room_type_rate_plans
      .includes(:occupancy_prices, :rate_plan, room_type: :rate_plans)
      .to_a
      .sort_by { |assignment| [ assignment.room_type.name.downcase, assignment.room_type_id ] }
    @assigned_room_types = @assignments.map(&:room_type)
    @booking_referenced_room_type_ids = @rate_plan.booking_rooms
      .where(room_type_id: @assigned_room_types.map(&:id))
      .distinct
      .pluck(:room_type_id)

    requested_room = @assigned_room_types.find { |room_type| room_type.id == room_type_id.to_i }
    @selected_room_type = requested_room || @assigned_room_types.first
    @selected_assignment = @assignments.find { |assignment| assignment.room_type_id == @selected_room_type&.id }
    @room_pricing ||= if @selected_room_type
      HotelPortal::RatePlanRoomPricing.from_assignment(
        @selected_assignment,
        room_type: @selected_room_type,
        sells_per_person: current_hotel.sells_per_person?
      )
    end
  end

  # Saving keeps staff on the plan's page, on the room category and tab they
  # were working in, so they can see what was saved and carry on.
  def redirect_to_rate_plan_editor(message, room_type_id: params[:room_type_id])
    redirect_to edit_hotel_rate_plan_path(current_hotel, @rate_plan, room_type_id: room_type_id.presence, tab: params[:tab].presence),
                notice: message, status: :see_other
  end

  def render_editor_errors(room_type_id: params[:room_type_id])
    load_rate_plan_editor(room_type_id: room_type_id)
    render "hotel_portal/rate_plans/edit", formats: :html, status: :unprocessable_content
  end

  # RoomTypeRatePlan#trigger_ari_sync fires per row, which would enqueue a
  # separate 500-day rate push for every room category touched. The callers
  # send one push afterwards instead.
  #
  # This has to wrap the whole transaction, not just the writes: the callback
  # is after_commit, so a flag reset inside the transaction block would already
  # be cleared by the time it runs.
  def with_batched_ari_sync
    previous_skip_ari_sync = Thread.current[:skip_ari_sync]
    Thread.current[:skip_ari_sync] = true
    yield
  ensure
    Thread.current[:skip_ari_sync] = previous_skip_ari_sync
  end

  def authorize_rate_plan_editor!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
