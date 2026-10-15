# frozen_string_literal: true

# Minting the QR a tablet pairs itself with.
#
# Deliberately its own resource rather than an action on the devices controller:
# a pairing is a separate, expiring thing that may never become a device, and
# the desk revokes one by discarding it rather than by deleting a tablet.
class HotelPortal::SigningDevicePairingsController < HotelPortal::BaseController
  before_action :require_grc_tablet_signing!
  before_action :authorize_manage_bookings!

  def create
    # Swept here rather than on a schedule: the table only grows when someone is
    # standing at this screen, so this is the one place that needs to tidy it.
    current_hotel.signing_device_pairings.stale.delete_all

    current_hotel.signing_device_pairings.create!(created_by_user: current_user)

    redirect_to hotel_signing_devices_path(current_hotel)
  end

  # Putting the QR away before it expires, for when it was shown to the room by
  # accident.
  def destroy
    current_hotel.signing_device_pairings.claimable.find_by(id: params[:id])&.destroy

    redirect_to hotel_signing_devices_path(current_hotel), notice: "Pairing code cancelled."
  end

  private

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
