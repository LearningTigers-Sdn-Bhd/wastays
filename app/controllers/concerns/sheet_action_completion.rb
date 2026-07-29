# frozen_string_literal: true

# Shared completion contract for Sheet-based action workflows.
#
# A sheet action finishes by emitting the `complete_sheet` stream action, which
# closes the dialog in the named frame and then navigates to the destination.
# Each family (bookings, folios, external accounts) wraps this with its own
# default frame so a stacked secondary sheet closes itself rather than the
# primary one.
#
# This deliberately does not serve the legacy OffcanvasTransactionCompletion,
# which targets a different frame and stream action.
module SheetActionCompletion
  extend ActiveSupport::Concern

  private

  def complete_sheet_action(destination:, notice:, frame:, html_status: :see_other)
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice
        render_sheet_action_completion(destination, frame: frame)
      end
      format.html { redirect_to destination, notice: notice, status: html_status }
    end
  end

  def render_sheet_action_completion(destination, frame:)
    render body: helpers.turbo_stream_action_tag(
      :complete_sheet,
      target: frame,
      url: destination
    ), content_type: Mime[:turbo_stream]
  end

  # Only same-origin paths inside the current hotel are honoured, so a crafted
  # return_to cannot bounce the operator off the property or off the host.
  def sheet_action_return_to(fallback:)
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
