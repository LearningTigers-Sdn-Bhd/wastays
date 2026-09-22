# frozen_string_literal: true

# Handing a stay to a waiting tablet.
#
# Nothing here opens anything on the tablet: a server cannot push a page to a
# browser that is not already listening. The tablet is parked on its idle
# screen holding an open stream, and this broadcasts down it. The tablet then
# navigates itself, which is why a tablet that is asleep or off that page
# receives nothing at all.
class HotelPortal::Bookings::SigningHandoffsController < HotelPortal::BaseController
  before_action :require_grc_tablet_signing!
  before_action :authorize_manage_bookings!
  before_action :set_booking

  def create
    device = current_hotel.signing_devices.find_by(public_token: params[:device_token])

    return redirect_back_with(alert: "Pick a tablet to send this to.") if device.nil?
    return redirect_back_with(alert: terms_missing_message) unless terms_ready?
    # Before `nothing_to_sign?`, which assigns the stay in memory to ask its
    # question and would make every tablet look busy with this booking.
    return redirect_back_with(alert: busy_message(device)) if occupied_elsewhere?(device)
    return redirect_back_with(alert: "Every guest on this booking has already signed.") if nothing_to_sign?(device)

    # Sent even when the tablet has not beaten recently. A stale heartbeat is
    # weaker evidence than a broken one would be damaging: a beat can fail for
    # reasons the tablet would survive, and refusing here would brick the
    # feature every time it did. So push, and say plainly what is known.
    device.hand_stay(@booking)
    Signing::HandStayToDevice.call(device: device)

    redirect_back_with(notice: sent_message(device))
  end

  private

  def sent_message(device)
    return "Sent to #{device.label}. The guest can sign there now." if device.live?

    "Sent to #{device.label}, but it has not checked in recently. " \
      "Check the tablet is awake and on its waiting screen."
  end

  # A tablet mid-stay must not be stolen. The guest standing at it is on the
  # card page, which does not listen to the device stream, so they would carry
  # on signing undisturbed -- and then be sent to the *new* booking's next
  # card, silently dropping whoever was left on theirs.
  #
  # Pushing the same stay again is not a conflict but a retry: the usual reason
  # is a tablet that slept through the first one.
  def occupied_elsewhere?(device)
    device.current_booking_id != @booking.id && device.busy?
  end

  def busy_message(device)
    "#{device.label} is still signing #{booking_label(device.current_booking)}. " \
      "Pick another tablet, or wait for it to finish."
  end

  # Enough for staff to walk over and look, without putting a guest's name in a
  # flash message that may sit on a shared screen.
  def booking_label(booking)
    return "room #{booking.room_numbers}" if booking.room_numbers.present?
    return "booking #{booking.reservation_number}" if booking.reservation_number.present?

    "another booking"
  end

  def nothing_to_sign?(device)
    # Asked of the stay being handed over, not of whatever the device was doing
    # before, so `hand_stay` is never called for a booking with nothing to do.
    device.current_booking = @booking
    device.next_booking_guest.nil?
  end

  # The card page refuses to collect a signature without terms to sign against,
  # so without them the tablet would land on a dead end. Better to say so here,
  # on the screen that has somewhere to send the reader.
  def terms_ready?
    current_hotel.guest_registration_card_terms.present?
  end

  def terms_missing_message
    "Add registration card terms in settings before sending a card to a tablet."
  end

  def set_booking
    @booking = current_hotel.bookings.includes(booking_guests: %i[guest guest_registration_card]).find(params[:booking_id])
  end

  def redirect_back_with(**flash_args)
    redirect_back(fallback_location: hotel_booking_workspace_path(current_hotel, @booking, tab: "guest_details"), **flash_args)
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
