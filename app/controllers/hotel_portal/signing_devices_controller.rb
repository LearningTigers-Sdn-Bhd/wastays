# frozen_string_literal: true

# Turning the tablet in someone's hands into a signing device.
#
# Staff reach this signed in, on the tablet itself. Enrolling mints a device
# token, parks the tablet on the token's own page, and then signs the staff
# member out: what is left on the counter can receive cards to sign and nothing
# else. That sign-out is the point of the screen, not a courtesy.
class HotelPortal::SigningDevicesController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def new
    @device = current_hotel.signing_devices.new(label: default_label)
    @existing_devices = current_hotel.signing_devices.recently_seen_first.limit(5)
  end

  def create
    device = current_hotel.signing_devices.create!(label: device_label)

    reset_session
    redirect_to signing_device_path(device.public_token), allow_other_host: false
  end

  private

  def device_label
    params.dig(:signing_device, :label).to_s.strip.presence || default_label
  end

  def default_label
    "Front desk tablet"
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
