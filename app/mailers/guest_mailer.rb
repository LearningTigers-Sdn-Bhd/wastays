class GuestMailer < ApplicationMailer
  def magic_link(guest, token)
    @guest = guest
    @magic_link_url = guest_verify_url(token: token)
    @expires_in = "24 hours"
    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))
    mail(to: @guest.email, subject: "Your WAStays login link")
  end
end
