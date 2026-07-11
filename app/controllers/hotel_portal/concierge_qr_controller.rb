class HotelPortal::ConciergeQrController < HotelPortal::BaseController
  before_action -> { require_feature!("ai_concierge_page") }
  before_action :set_breadcrumbs, only: [ :show ]

  def show
    @concierge_url = ::Concierge::ConciergeUrl.for(
      current_hotel,
      host: request.host_with_port,
      scheme: request.scheme
    )

    respond_to do |format|
      format.html do
        @qr_svg = ::Concierge::QrSvg.for(@concierge_url).html_safe
      end
      format.svg do
        svg = ::Concierge::QrSvg.for(@concierge_url)
        send_data svg, type: "image/svg+xml", disposition: "attachment",
                       filename: "concierge-qr-#{current_hotel.slug}.svg"
      end
      format.png do
        png = ::Concierge::QrSvg.png(@concierge_url)
        send_data png, type: "image/png", disposition: "attachment",
                       filename: "concierge-qr-#{current_hotel.slug}.png"
      end
    end
  end

  private

  def set_breadcrumbs
    override_breadcrumbs(
      { label: "System" },
      { label: "Settings", path: hotel_general_settings_path(current_hotel) },
      { label: "Concierge QR", path: hotel_concierge_qr_path(current_hotel) }
    )
  end
end
