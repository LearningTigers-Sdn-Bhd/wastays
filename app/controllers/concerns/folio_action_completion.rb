# frozen_string_literal: true

# Sheet-based completion contract for HotelPortal::Folios::Actions.
#
# Folio actions are their own family: this targets the `folio_action_sheet`
# Turbo Frame and emits the `complete_sheet` stream action. It shares no names,
# frames, or helpers with BookingActionCompletion or the legacy
# OffcanvasTransactionCompletion.
module FolioActionCompletion
  extend ActiveSupport::Concern

  private

  def complete_folio_action(destination:, notice:, html_status: :see_other, frame: "folio_action_sheet")
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice
        render_folio_action_completion(destination, frame: frame)
      end
      format.html { redirect_to destination, notice: notice, status: html_status }
    end
  end

  def render_folio_action_completion(destination, frame: "folio_action_sheet")
    render body: helpers.turbo_stream_action_tag(
      :complete_sheet,
      target: frame,
      url: destination
    ), content_type: Mime[:turbo_stream]
  end

  def folio_action_return_to(fallback:)
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
