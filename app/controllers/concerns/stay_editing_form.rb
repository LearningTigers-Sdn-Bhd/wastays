# frozen_string_literal: true

# Shared form helpers for the intent-scoped Stay-editing Sheets
# (Dates / Room / Rate). Each controller renders one intent; this concern
# holds the value preparation and hotel-time helpers they have in common so
# no business rule is duplicated across them.
module StayEditingForm
  extend ActiveSupport::Concern

  include GroupLifecycleTargeting

  private

  # Seeds the shared instance variables every Stay-editing form needs. Values
  # come from a submitted/proposed `booking` param when present, otherwise from
  # the persisted booking, so the same form re-renders faithfully on failure and
  # pre-fills from a Stay View drag proposal.
  def prepare_stay_values
    @room = @booking.booking_rooms.first
    booking_values = params.fetch(:booking, ActionController::Parameters.new)
    @check_in_value = form_datetime(booking_values[:check_in].presence || @booking.check_in, :check_in)
    @check_out_value = form_datetime(booking_values[:check_out].presence || @booking.check_out, :check_out)
    @check_in_date = @check_in_value.to_s.split("T").first
    @check_out_date = @check_out_value.to_s.split("T").first
    @room_type_id = booking_values[:room_type_id].presence || @room&.room_type_id
    @room_number = booking_values[:room_number].presence || @room&.room_number
    @rate_selection = if booking_values.key?(:rate_selection)
      booking_values[:rate_selection].to_s
    else
      ::Bookings::RateSelection.current(@room).token
    end
    @proposal_kind = params[:proposal_kind].presence_in(%w[move dates])
    @selected_booking_ids = Array(params[:booking_ids]).reject(&:blank?).map(&:to_s)
    @target_scope = params[:target_scope].presence || "individual"
    @current_tax_total = Booking.non_tourism_tax_total_for(@booking.tax_lines)
  end

  def scheduled_value(value, kind)
    ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value:, kind:)
  end

  def form_datetime(value, kind)
    time = value.respond_to?(:in_time_zone) ? value : scheduled_value(value, kind)
    time.in_time_zone(current_hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")
  end

  def add_errors(errors)
    Array(errors).flatten.compact.each { |message| @booking.errors.add(:base, message) }
  end

  def ensure_eligible!
    return if lifecycle_booking_eligible?(@booking, :amend_stay)

    redirect_to @return_to, alert: "This booking can no longer be edited.", status: :see_other
  end
end
