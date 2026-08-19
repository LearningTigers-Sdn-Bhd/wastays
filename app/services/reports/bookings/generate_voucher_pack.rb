# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

module Reports
  module Bookings
    # Every room in a group, one voucher per page, in one file. A group organiser prints
    # once and hands each guest their own page.
    #
    # Each page is a whole voucher rather than a continuation of the one before it: its own
    # masthead, its own confirmation code and QR, its own policies. Guests in a group are
    # not a party — they arrive separately and a leader may never pass the terms on — so a
    # page has to stand on its own once it is torn off the stack.
    #
    # Cancelled rooms are printed too. A cancelled voucher carries its status badge, so it
    # reads as cancelled rather than as an entitlement, and dropping it silently would leave
    # the organiser counting pages against rooms and coming up short.
    class GenerateVoucherPack
      EmptyGroupError = Class.new(StandardError)

      THEME = HotelPortal::Reports::Exports::PdfTheme

      def initialize(group_booking)
        @group_booking = group_booking
      end

      def generate
        bookings = ordered_bookings
        raise EmptyGroupError, "group #{@group_booking.id} has no bookings to print" if bookings.empty?

        pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
        THEME.configure_font(pdf)

        frame = nil
        bookings.each_with_index do |booking, index|
          pdf.start_new_page unless index.zero?
          frame = Reports::Bookings::GenerateVoucher.new(booking).render_into(pdf)
        end

        # Every page opens a voucher of its own, so none of them is a continuation needing a
        # running head to say what it belongs to.
        frame.stamp_page_furniture(masthead_pages: (1..pdf.page_count).to_a)
        pdf.render
      end

      private

      def ordered_bookings
        @group_booking.bookings.includes(booking_rooms: :room_type).order(:group_position, :id).to_a
      end

      def document_info
        {
          Title: "Booking Vouchers - #{@group_booking.formatted_reservation_number}",
          Author: "WAStays",
          Creator: "WAStays",
          CreationDate: Time.current
        }
      end
    end
  end
end
