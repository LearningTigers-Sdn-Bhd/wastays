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

    it 'identifies due out not checked out' do
      create(:booking, status: 'checked_in', hotel: hotel, check_out: business_date)
      result = service.call
      expect(result[:blocked_details]["due_out_not_checked_out"]).not_to be_empty
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
