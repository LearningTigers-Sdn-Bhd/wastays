# frozen_string_literal: true

module OffcanvasTransactionCompletion
  extend ActiveSupport::Concern

  private

  def offcanvas_transaction_response(destination:, notice:, html_status: :see_other)
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = notice
        render_offcanvas_completion(destination)
      end
      format.html { redirect_to destination, notice: notice, status: html_status }
    end
  end

  def render_offcanvas_completion(destination)
    render body: helpers.turbo_stream_action_tag(
      :complete_offcanvas,
      target: "offcanvas_drawer",
      url: destination
    ), content_type: Mime[:turbo_stream]
  end

  def offcanvas_return_to(fallback:)
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
