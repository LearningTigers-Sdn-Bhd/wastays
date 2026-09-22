# frozen_string_literal: true

# Managing the tablets a property collects signatures on.
#
# Enrolment does not happen here. A tablet cannot be paired from the desk's own
# browser -- the device that ends up holding the token has to be the one that
# claims it -- so this screen mints a pairing and shows it, and the tablet
# claims it through Public::SigningDevicePairingsController.
class HotelPortal::SigningDevicesController < HotelPortal::BaseController
  before_action :require_grc_tablet_signing!
  before_action :authorize_manage_bookings!
  before_action :set_device, only: %i[update destroy]

  def index
    @devices = current_hotel.signing_devices.recently_seen_first.includes(:current_booking)
    # Only one live pairing is shown at a time: two QRs on a screen is an
    # invitation to scan the wrong one.
    @pairing = current_hotel.signing_device_pairings.claimable.order(created_at: :desc).first
  end

  def update
    if @device.update(label: device_label)
      redirect_to hotel_signing_devices_path(current_hotel), notice: "Renamed to #{@device.label}."
    else
      redirect_to hotel_signing_devices_path(current_hotel), alert: @device.errors.full_messages.to_sentence
    end
  end

  # Revoking is a destroy rather than a flag: the token is the whole of the
  # device's access, so the only honest way to withdraw it is for the row to
  # stop existing. A tablet still sitting on the idle screen 404s on its next
  # heartbeat.
  def destroy
    label = @device.label
    @device.destroy!

    redirect_to hotel_signing_devices_path(current_hotel),
      notice: "#{label} can no longer receive registration cards."
  end

  private

  def set_device
    @device = current_hotel.signing_devices.find(params[:id])
  end

  def device_label
    params.dig(:signing_device, :label).to_s.strip.presence || SigningDevice::DEFAULT_LABEL
  end

  # The property must have been granted the feature by a superadmin. Checked on
  # every entry point rather than trusted from the navigation: the nav only
  # hides the link, and a hotel can have the grant withdrawn while a staff
  # member is sitting on one of these pages.
  def require_grc_tablet_signing!
    return if current_hotel.grc_tablet_signing_enabled?

    redirect_to hotel_dashboard_path(current_hotel),
      alert: "Registration card tablet signing is not enabled for this property."
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
