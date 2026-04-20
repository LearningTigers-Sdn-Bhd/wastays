class BookingMailer < ApplicationMailer
  def invoice(booking)
    @booking = booking
    @hotel   = booking.hotel
    @nights  = (booking.check_out - booking.check_in).to_i

    attachments.inline["long-logo.png"] = File.read(
      Rails.root.join("app/assets/images/logo/long-logo.png")
    )

    attachments["wastays-invoice-#{booking.confirmation_token}.pdf"] = {
      mime_type: "application/pdf",
      content:   InvoicePdfService.new(booking).generate
    }

    mail(
      to:      booking.guest_email,
      subject: "Your booking is confirmed — Invoice #{booking.confirmation_token}"
    )
  end
end
