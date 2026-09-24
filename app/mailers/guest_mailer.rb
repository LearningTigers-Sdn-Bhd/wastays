class GuestMailer < ApplicationMailer
  def magic_link(guest, token)
    @guest = guest
    @magic_link_url = guest_verify_url(token: token)
    @expires_in = "24 hours"
    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))
    mail(to: @guest.email, subject: "Your WAStays login link")
  end

  # The stay link for one stay. It opens the Checked-in Concierge page, not the
  # Guest Portal, so the mail carries no login token. The guest still enters the
  # confirmation code one time on each device.
  def stay_link(stay_access, email)
    @stay_access = stay_access
    @booking = stay_access.booking
    @hotel = @booking.hotel
    @stay_url = Concierge::ConciergeUrl.stay(@hotel, stay_access.stay_access_id)
    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))
    mail(to: email, subject: "Your stay at #{@hotel.name}")
  end
end
