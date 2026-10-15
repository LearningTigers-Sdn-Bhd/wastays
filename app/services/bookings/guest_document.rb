# frozen_string_literal: true

module Bookings
  # Builds the PDFs a guest can download for one booking.
  #
  # The Guest Portal and the stay page both offer these documents. The bytes,
  # the filename, and the reason a document is unavailable all live here, so
  # neither controller has to repeat a rescue.
  class GuestDocument
    KINDS = %i[receipt invoice summary voucher_pack e_invoice].freeze

    Result = ApplicationResult.define(:bytes, :filename)

    def initialize(booking:, kind:, submission: nil)
      @booking = booking
      @kind = kind.to_sym
      @submission = submission
    end

    def call
      raise ArgumentError, "Unknown guest document: #{kind}" unless kind.in?(KINDS)

      send(kind)
    rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
      Result.failure("No finalized guest invoice is available for this booking.")
    rescue ::Reports::Bookings::GenerateVoucherPack::EmptyGroupError
      Result.failure("This group has no rooms to print.")
    end

    private

    attr_reader :booking, :kind, :submission

    def receipt
      document(::Reports::Bookings::GenerateConfirmation.new(booking).generate, "receipt")
    end

    def invoice
      bytes = ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: booking).generate
      document(bytes, "invoice")
    end

    def e_invoice
      return Result.failure("No e-invoice is available for this booking.") if submission.blank?

      bytes = ::EInvoicePdfService.new(booking, submission: submission).generate
      document(bytes, "e-invoice", reference: submission.internal_id.presence)
    end

    # A room in a group reports the group's position, because that is the
    # position anyone settles.
    def summary
      subject = booking.group_booking || booking
      bytes = if subject.is_a?(GroupBooking)
        ::Reports::Bookings::GenerateBookingSummary.new(group_booking: subject).generate
      else
        ::Reports::Bookings::GenerateBookingSummary.new(booking: subject).generate
      end

      document(bytes, "booking-summary", reference: subject.confirmation_token)
    end

    def voucher_pack
      group = booking.group_booking
      return Result.failure("This booking is not part of a group.") if group.blank?

      bytes = ::Reports::Bookings::GenerateVoucherPack.new(group).generate
      document(bytes, "vouchers", reference: group.confirmation_token)
    end

    def document(bytes, label, reference: nil)
      name = reference.presence || booking.confirmation_token
      Result.success(bytes: bytes, filename: "wastays-#{label}-#{name}.pdf")
    end
  end
end
