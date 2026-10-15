# frozen_string_literal: true

module HotelPortal
  # How a tablet reads in the desk's picker.
  #
  # Staff are choosing where to send a guest, so the only thing worth saying is
  # whether pressing send will work. Three answers, in the order they override
  # each other: not listening at all, listening but mid-stay, ready.
  module SigningDevicesHelper
    # Kept out of the option text: a tablet already holding *this* stay is a
    # retry target, not a conflict, and the handoff accepts it.
    def signing_device_status(device, booking)
      return :offline unless device.live?
      return :busy if device.current_booking_id != booking.id && device.busy?

      :ready
    end

    def signing_device_option_label(device, booking)
      case signing_device_status(device, booking)
      when :offline then "#{device.label} — not connected"
      when :busy    then "#{device.label} — busy"
      else device.label
      end
    end
  end
end
