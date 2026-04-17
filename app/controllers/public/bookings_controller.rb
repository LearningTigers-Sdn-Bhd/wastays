class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @booking = Booking.find_by!(confirmation_token: params[:id])
    @hotel = @booking.hotel
    @booking_rooms = @booking.booking_rooms
    @pre_checkin = @booking.pre_checkin || @booking.create_pre_checkin!(
      status: "pending",
      document_status: "pending",
      signature_status: "pending"
    )
    @qr_svg = build_qr_svg(@booking.confirmation_token)
  end

  private

  def build_qr_svg(token)
    qr = RQRCode::QRCode.new(token)
    svg = qr.as_svg(
      color: "0a2e29",
      shape_rendering: "crispEdges",
      module_size: 6,
      offset: 0,
      viewbox: true,
      standalone: true,
      use_path: true
    )
    svg.gsub(/\s+(width|height)="[^"]*"/, "")
       .sub(/<svg/, '<svg style="width:100%;height:100%;display:block;"')
       .html_safe
  end
end
