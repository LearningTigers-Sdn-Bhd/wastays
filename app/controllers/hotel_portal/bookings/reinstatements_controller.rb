# frozen_string_literal: true

class HotelPortal::Bookings::ReinstatementsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion
  include GroupLifecycleTargeting

  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    return batch_reinstate if selected_lifecycle_batch?(@booking)

    result = Bookings::ReinstateReservation.new(
      booking: @booking,
      params: booking_params.slice(:booking_rooms_attributes),
      user: current_user,
      options: {
        override_night_audit: true,
        reason: params[:retroactive_reason]
      }
    ).call

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
        notice: "Booking reinstated and checked in successfully."
      )
    else
      redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Failed to reinstate booking: #{result.error}"
    end
  end

  private

  def batch_reinstate
    attributes = batch_reinstatement_params
    # Use the shared target validation before handing the child-specific data
    # to the transactional service.
    selected = selected_lifecycle_bookings(fallback_booking: @booking, action: :reinstate)
    selected_ids = selected.map { |booking| booking.id.to_s }
    raise BatchTargetError, "Every selected booking must be configured before reinstatement." unless (selected_ids - attributes.keys).empty?

    attributes = attributes.slice(*selected_ids)

    result = Bookings::ReinstateGroup.call(
      group_booking: @booking.group_booking,
      booking_attributes: attributes,
      user: current_user,
      options: { override_night_audit: true, reason: params[:retroactive_reason] }
    )

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
        notice: batch_lifecycle_notice(result.bookings, "reinstated and checked in")
      )
    else
      redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Failed to reinstate group: #{result.error}", status: :see_other
    end
  rescue BatchTargetError => e
    redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: e.message, status: :see_other
  end

  def batch_reinstatement_params
    raw = params.fetch(:reinstatements, ActionController::Parameters.new)
    raw.to_unsafe_h.transform_values do |attributes|
      ActionController::Parameters.new(attributes).permit(
        booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
      ).to_h
    end
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
    )
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
