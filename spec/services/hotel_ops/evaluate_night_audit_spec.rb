require 'rails_helper'

RSpec.describe HotelOps::EvaluateNightAudit do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.current - 1.day }
  let(:service) { described_class.new(hotel: hotel, business_date: business_date) }

  describe '#call' do
    it 'returns a hash with blocked_details, exceptions, and summary' do
      result = service.call
      expect(result).to have_key(:blocked_details)
      expect(result).to have_key(:exceptions)
      expect(result).to have_key(:summary)
    end

    it 'identifies stale checked-in due outs as blockers' do
      create(:booking, status: 'checked_in', hotel: hotel, check_out: business_date)
      result = service.call
      expect(result[:blocked_details]["due_out_not_checked_out"]).not_to be_empty
    end

    it 'treats review_due_out bookings as warnings rather than blockers' do
      booking = create(:booking, status: 'review_due_out', hotel: hotel, check_out: business_date)

      result = service.call

      expect(result[:blocked_details]["due_out_not_checked_out"]).to be_empty
      expect(result[:exceptions]["review_due_out"].sole["booking_id"]).to eq(booking.id)
    end

    it 'omits posting-generated blockers during pre-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :pre_close).call

      expect(result[:blocked_details]).not_to have_key("missing_folio")
      expect(result[:blocked_details]).not_to have_key("missing_nightly_charges")
    end

    it 'includes posting-generated blockers during post-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :post_close).call

      expect(result[:blocked_details]["missing_folio"].first["booking_id"]).to eq(booking.id)
    end

    it 'identifies large balance exceptions' do
      booking = create(:booking, status: 'checked_in', hotel: hotel)
      folio = create(:booking_folio, booking: booking)
      create(:folio_transaction, :charge, booking_folio: folio, amount: 2000, category: "other")

      result = service.call
      expect(result[:exceptions]["folio_balance_exceptions"]).not_to be_empty
      expect(result[:exceptions]["folio_balance_exceptions"].first["reason"]).to eq("Large outstanding balance")
    end
  end
end
