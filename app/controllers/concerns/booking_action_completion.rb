# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::Bookings::Actions.
#
# Deliberately isolated from OffcanvasTransactionCompletion: it targets the
# `booking_action_sheet` Turbo Frame and emits the `complete_sheet` stream
# action. It shares no names, frames, or helpers with the legacy Offcanvas
# implementation.
module BookingActionCompletion
  extend ActiveSupport::Concern

  private

  def complete_booking_action(destination:, notice:, html_status: :see_other, frame: "booking_action_sheet")
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice
        render_booking_action_completion(destination, frame: frame)
      end
      format.html { redirect_to destination, notice: notice, status: html_status }
    end
  end

  def render_booking_action_completion(destination, frame: "booking_action_sheet")
    render body: helpers.turbo_stream_action_tag(
      :complete_sheet,
      target: frame,
      url: destination
    ), content_type: Mime[:turbo_stream]
  end

  def booking_action_return_to(fallback:)
    candidate = params[:return_to].presence
    return fallback if candidate.blank?

    uri = URI.parse(candidate)
    if uri.host.present? || uri.scheme.present?
      return fallback unless "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}" == request.base_url

      uri = URI.parse(uri.request_uri)
    end

    return fallback if uri.path.blank?
    return fallback unless uri.path.start_with?("/hotel/#{current_hotel.to_param}/")

    uri.to_s
  rescue URI::InvalidURIError
    fallback
  end
end
