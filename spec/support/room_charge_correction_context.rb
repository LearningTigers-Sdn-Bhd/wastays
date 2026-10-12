# frozen_string_literal: true

RSpec.shared_context "completed room-charge correction" do
  let(:correction_date) { Date.current - 1.day }
  let(:night_count) { 1 }
  let(:hotel) { create(:hotel, status: "live", sst_enabled: true) }
  let(:actor) { create(:user, account: hotel.account, role: "hotel_staff") }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100, quantity: 10) }
  let(:booking) do
    create(:booking, :direct_hotel_payment, hotel: hotel, status: "completed", guest_country: "Malaysia",
      check_in: correction_date, check_out: correction_date + night_count.days)
  end
  let(:room) { create(:booking_room, booking: booking, room_type: room_type, rate_plan: room_type.standard_rate_plan, subtotal: 100 * night_count, room_number: "101") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, is_primary: true) }
  let(:correction_input) { { nightly_amounts: amounts_for("86.40"), correction_reason: "Agreed room rate was entered incorrectly." } }

  # Same tax-inclusive amount for every night of the stay, keyed by ISO date.
  def amounts_for(amount)
    (0...night_count).to_h { |offset| [ (correction_date + offset).iso8601, amount ] }
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    (Bookings::CorrectRoomCharges::PERMISSIONS + %w[manage_folio_windows view_bookings view_folios]).each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |permission| permission.name = slug.humanize }
    end
    create(:user_hotel_access, hotel: hotel, user: actor, role: role)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.find_or_create_by!(primary_tax_key: "sst_tax")
    room
    folio
    snapshot = Bookings::BuildFinancialSnapshot.new(hotel: hotel, booking: booking, room_type: room_type,
      rate_plan: room.rate_plan, check_in: booking.check_in, check_out: booking.check_out,
      guest_country: booking.guest_country, manual_total_amount: 100 * night_count).call
    room.update!(nightly_rate_snapshot: snapshot.nightly_rate_snapshot, subtotal: snapshot.room_total)
    booking.update!(tax_posting_snapshot: snapshot.tax_posting_snapshot, tax_lines: snapshot.tax_lines,
      total_amount: snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines))
    dates = Bookings::ScheduledStay.stay_dates(hotel: hotel, check_in: booking.check_in, check_out: booking.check_out)
    dates.each do |date|
      audit = if date < Date.current
        create(:hotel_business_date, hotel: hotel, business_date: date, status: "closed")
        create(:night_audit, hotel: hotel, business_date: date, status: "completed")
      end
      Folios::Reads::ForecastedChargeLines.call(booking: booking, dates: [ date ]).each do |line|
        key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: date, charge_kind: line[:charge_kind], identity: line[:identity])
        create(:folio_transaction, booking_folio: folio, source_booking: booking, user: actor, posting_date: date,
          transaction_type: "charge", transaction_code: line[:transaction_code], category: line[:category], amount: line[:amount],
          night_audit: audit, metadata: { nightly_charge_key: key, posting_source: "night_audit", night_audit_id: audit&.id,
            stay_date: date.iso8601, charge_kind: line[:charge_kind], forecast_identity: line[:identity].to_s, tax_line: line[:tax_line] }.compact)
      end
    end
  end

  def review_room_correction(**attributes)
    Bookings::CorrectRoomCharges.call(booking: booking, user: actor, **correction_input, **attributes)
  end

  def confirm_room_correction(review, **attributes)
    review_room_correction(confirm: true, correction_review_token: review.correction_review_token, **attributes)
  end
end
