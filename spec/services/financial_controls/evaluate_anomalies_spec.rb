require "rails_helper"

RSpec.describe FinancialControls::EvaluateAnomalies do
  let(:hotel) { create(:hotel) }
  let(:service) { described_class.new(hotel) }

  describe "#call" do
    it "returns a report structure" do
      report = service.call
      expect(report).to have_key(:unbalanced_folios)
      expect(report).to have_key(:audit_sync_lags)
      expect(report).to have_key(:override_abuse)
    end

    context "with unbalanced folios" do
      it "detects closed bookings with non-zero balances" do
        booking = create(:booking, hotel: hotel, status: "completed")
        folio = create(:booking_folio, booking: booking, hotel: hotel, status: "closed")

        # Manually inject a transaction to create a balance
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100.0)

        report = service.call
        expect(report[:unbalanced_folios].count).to eq(1)
        expect(report[:unbalanced_folios].first[:confirmation_token]).to eq(booking.confirmation_token)
        expect(report[:unbalanced_folios].first[:balance]).to eq(100.0)
      end

      it "ignores balanced closed folios" do
        booking = create(:booking, hotel: hotel, status: "completed")
        create(:booking_folio, booking: booking, hotel: hotel, status: "closed")
        # Balance is 0

        report = service.call
        expect(report[:unbalanced_folios]).to be_empty
      end
    end

    context "with audit sync lags" do
      it "detects old business dates that are not closed" do
        old_date = 5.days.ago.to_date
        create(:hotel_business_date, hotel: hotel, business_date: old_date, status: "open")

        report = service.call
        expect(report[:audit_sync_lags].count).to eq(1)
        expect(report[:audit_sync_lags].first[:business_date]).to eq(old_date)
      end

      it "ignores recently opened dates" do
        create(:hotel_business_date, hotel: hotel, business_date: Date.current, status: "open")

        report = service.call
        expect(report[:audit_sync_lags]).to be_empty
      end
    end

    context "with override abuse" do
      it "flags when more than 5 overrides happen in 24h" do
        6.times do
          create(:financial_audit_event, hotel: hotel, event_type: "closed_date_override_posted", occurred_at: Time.current)
        end

        report = service.call
        expect(report[:override_abuse][:count]).to eq(6)
      end

      it "ignores low volume of overrides" do
        3.times do
          create(:financial_audit_event, hotel: hotel, event_type: "closed_date_override_posted", occurred_at: Time.current)
        end

        report = service.call
        expect(report[:override_abuse]).to be_nil
      end
    end
  end
end
