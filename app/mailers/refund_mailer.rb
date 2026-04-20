class RefundMailer < ApplicationMailer
  def completed(refund_request)
    @refund_request = refund_request
    @booking = refund_request.booking
    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))
    mail(to: @booking.guest_email, subject: "Your refund is on its way — WAStays")
  end
end
