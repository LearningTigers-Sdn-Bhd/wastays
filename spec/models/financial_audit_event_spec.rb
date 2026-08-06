# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinancialAuditEvent, type: :model do
  subject(:event) { build(:financial_audit_event) }

  it { is_expected.to belong_to(:hotel) }
  it { is_expected.to belong_to(:actor).optional }
  it { is_expected.to belong_to(:folio_transaction).optional }
  it { is_expected.to belong_to(:booking_folio).optional }
  it { is_expected.to belong_to(:booking).optional }
  it { is_expected.to belong_to(:payment_transaction).optional }
  it { is_expected.to belong_to(:refund_request).optional }
  it { is_expected.to belong_to(:night_audit).optional }
  it { is_expected.to belong_to(:hotel_business_date).optional }
  it { is_expected.to validate_presence_of(:business_date) }
  it { is_expected.to validate_presence_of(:event_type) }
  it { is_expected.to validate_inclusion_of(:event_type).in_array(described_class::EVENT_TYPES) }
  it { is_expected.to validate_presence_of(:source) }
  it { is_expected.to validate_presence_of(:occurred_at) }

  it "allows empty metadata but not nil" do
    expect(build(:financial_audit_event, metadata: {})).to be_valid

    event = build(:financial_audit_event, metadata: nil)
    expect(event).not_to be_valid
  end

  it "prevents updates" do
    event = create(:financial_audit_event)

    expect(event.update(event_type: "night_audit_started")).to be(false)
    expect(event.errors[:base]).to include("Financial audit events are immutable.")
  end

  it "prevents deletes" do
    event = create(:financial_audit_event)

    expect(event.destroy).to be(false)
    expect(event.errors[:base]).to include("Financial audit events are immutable and cannot be deleted.")
  end
end
