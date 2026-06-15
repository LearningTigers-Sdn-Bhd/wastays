require "rails_helper"

RSpec.describe NightAudits::Run do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, :without_current_business_date, account: account) }
  let(:user) { create(:user, account: account, role: "superadmin") }
  let(:business_date) { 2.days.ago.to_date }

  def create_balanced_folio(booking, charge_amount: 200.0, payment_amount: charge_amount)
    folio = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 10_000 + booking.id)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: charge_amount, posting_date: booking.check_in)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: payment_amount, posting_date: booking.check_out)
    folio
  end

  before do
    allow(Financials::CreateJournalBatch).to receive(:call)
    # Create a blocker: a checked-in booking missing its required check-in timestamp
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      checked_in_at: nil)
    create_balanced_folio(booking)
  end

  context "when force_roll is false (default)" do
    subject(:run_audit) do
      described_class.new(
        hotel: hotel,
        business_date: business_date,
        performed_by_user: user,
        trigger_mode: "manual",
        force_roll: false
      ).call
    end

    it "blocks the audit and does not open the next date" do
      result = run_audit

      expect(result.success?).to be(false)
      expect(result.night_audit).to be_blocked
      expect(hotel.hotel_business_dates.find_by!(business_date: business_date)).to be_audit_blocked
      expect(hotel.hotel_business_dates.find_by(business_date: business_date + 1.day)).to be_nil
    end
  end

  context "when force_roll is true" do
    subject(:run_audit) do
      described_class.new(
        hotel: hotel,
        business_date: business_date,
        performed_by_user: user,
        trigger_mode: "manual",
        force_roll: true,
        notes: "Manager accepted unresolved blockers"
      ).call
    end

    it "completes the audit, force-closes the business date, and opens the next date" do
      result = run_audit

      puts "AUDIT ERROR: #{result.error}" if result.error
      expect(result.success?).to be(true)
      expect(result.night_audit).to be_completed
      expect(result.night_audit.force_closed).to be(true)

      biz_date_record = hotel.hotel_business_dates.find_by!(business_date: business_date)
      expect(biz_date_record).to be_force_closed

      expect(hotel.hotel_business_dates.find_by!(business_date: business_date + 1.day)).to be_open
    end

    it "records the force-roll financial audit event" do
      result = run_audit

      expect(result.night_audit.financial_audit_events.pluck(:event_type)).to include("night_audit_force_rolled")

      force_roll_event = result.night_audit.financial_audit_events.find_by!(event_type: "night_audit_force_rolled")
      expect(force_roll_event.reason).to eq("Night audit force-rolled with blockers")
    end
  end
end
