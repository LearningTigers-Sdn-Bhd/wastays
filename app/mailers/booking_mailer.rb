class BookingMailer < ApplicationMailer
  def receipt(booking)
    @booking = booking
    @hotel   = booking.hotel
    @nights  = (booking.check_out.to_date - booking.check_in.to_date).to_i

    attachments.inline["long-logo.png"] = File.read(
      Rails.root.join("app/assets/images/logo/long-logo.png")
    )

    attachments["wastays-booking-confirmation-#{booking.confirmation_token}.pdf"] = {
      mime_type: "application/pdf",
      content:   ReceiptPdfService.new(booking).generate
    }

    mail(
      to:      booking.guest_email,
      subject: "Your booking is confirmed - #{booking.confirmation_token}"
    )
  end

  def invoice(booking)
    @booking = booking
    @hotel   = booking.hotel
    @nights  = (booking.check_out.to_date - booking.check_in.to_date).to_i

    attachments.inline["long-logo.png"] = File.read(
      Rails.root.join("app/assets/images/logo/long-logo.png")
    )

    attachments["wastays-invoice-#{booking.confirmation_token}.pdf"] = {
      mime_type: "application/pdf",
      content:   ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: booking).generate
    }

    mail(
      to:      booking.guest_email,
      subject: "Your invoice — #{booking.confirmation_token}"
    )
  end
end
