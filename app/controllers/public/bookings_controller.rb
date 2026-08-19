class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    booking = Booking.with_confirmation_token(params[:id]).first!
    @booking = Public::BookingPresenter.new(booking, view_context)
    @hotel = Public::HotelPresenter.new(@booking.hotel, view_context)
    @booking_rooms = @booking.booking_rooms
    @display_currency = DisplayCurrencyResolver.new(params: params, cookies: cookies, request: request).call
    pre_checkin_result = GuestArrival::StartPreCheckin.new(booking).call
    @pre_checkin = pre_checkin_result.pre_checkin if pre_checkin_result.success?
    @qr_data_url = Concierge::QrSvg.data_url(@booking.confirmation_token)
  end

  def receipt
    confirmation
  end

  def confirmation
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = Reports::Bookings::GenerateConfirmation.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-booking-confirmation-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def invoice
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    head :not_found
  end

  def voucher
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = Reports::Bookings::GenerateVoucher.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-voucher-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  # A group organiser holds the group's own code; each guest holds their room's. Either one
  # reaches the pack, so the organiser can print the set from the link they were sent.
  def voucher_pack
    group_booking = resolve_group_booking!
    pdf_bytes = Reports::Bookings::GenerateVoucherPack.new(group_booking).generate
    send_data pdf_bytes,
      filename: "wastays-vouchers-#{group_booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue Reports::Bookings::GenerateVoucherPack::EmptyGroupError
    head :not_found
  end

  def summary
    subject = resolve_summary_subject!
    pdf_bytes = if subject.is_a?(GroupBooking)
      Reports::Bookings::GenerateBookingSummary.new(group_booking: subject).generate
    else
      Reports::Bookings::GenerateBookingSummary.new(booking: subject).generate
    end
    send_data pdf_bytes,
      filename: "wastays-booking-summary-#{subject.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  private

  # A room that belongs to a group reports the group's position, because that is the
  # position anyone settles.
  def resolve_summary_subject!
    booking = Booking.with_confirmation_token(params[:id]).includes(:group_booking).first
    return booking.group_booking || booking if booking

    GroupBooking.with_confirmation_token(params[:id]).first!
  end

  def resolve_group_booking!
    booking = Booking.with_confirmation_token(params[:id]).includes(:group_booking).first
    group_booking = booking&.group_booking
    return group_booking if group_booking
    raise ActiveRecord::RecordNotFound, "booking #{params[:id]} belongs to no group" if booking

    GroupBooking.with_confirmation_token(params[:id]).first!
  end
end
