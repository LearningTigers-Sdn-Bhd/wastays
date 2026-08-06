# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::ReopenForCorrection do
  let(:booking) { create(:booking) }
  let(:folio) { create(:booking_folio, booking: booking, status: "closed", invoice_number: 42) }
  let(:user) { create(:user) }
  let!(:transaction) { create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "other") }

  def grant_correction_permission
    permission = Permission.find_or_create_by!(slug: "post_folio_corrections") { |record| record.name = "Post Folio Corrections" }
    role = create(:role, account: user.account)
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: booking.hotel, role: role)
  end

  def call_service(reason: "Incorrect checkout", note: "Reopen to post correction")
    described_class.call(
      booking_folio: folio,
      user: user,
      correction_reason: reason,
      correction_note: note
    )
  end

  it "reopens a closed folio with permission and records an audit event" do
    grant_correction_permission
    transaction_attributes = transaction.attributes

    expect { @result = call_service }.to change(FinancialAuditEvent, :count).by(1)

    expect(@result.success?).to be(true)
    expect(folio.reload).to be_open
    expect(folio.invoice_number).to eq(42)
    expect(transaction.reload.attributes).to eq(transaction_attributes)

    event = FinancialAuditEvent.last
    expect(event.event_type).to eq("folio_reopened_for_correction")
    expect(event.reason).to eq("Incorrect checkout")
    expect(event.metadata).to include(
      "correction_note" => "Reopen to post correction",
      "invoice_number" => 42,
      "previous_status" => "closed",
      "new_status" => "open"
    )
  end

  it "marks a canonical folio invoice under correction" do
    grant_correction_permission
    folio.update_columns(invoice_number: nil, invoice_year: nil, invoice_reference: nil)
    folio.update_column(:status, "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100)
    Folios::Lifecycle::CloseFolio.call(folio:, user: create(:user, :superadmin), reason: "Settled")

    result = call_service

    expect(result).to be_success
    expect(folio.reload.invoice).to be_under_correction
  end

  it "requires a staff user with correction permission" do
    expect(call_service.success?).to be(false)

    result = described_class.call(
      booking_folio: folio,
      user: nil,
      correction_reason: "Incorrect checkout",
      correction_note: "Reopen to post correction"
    )
    expect(result.error).to include("staff user")
  end

  it "requires a reason and note" do
    grant_correction_permission

    expect(call_service(reason: "").error).to include("reason")
    expect(call_service(note: "").error).to include("note")
  end

  it "rejects an already-open folio" do
    grant_correction_permission
    folio.update_column(:status, "open")

    expect(call_service.error).to eq("Folio is already open.")
  end

  it "blocks reopening while Night Audit is running" do
    grant_correction_permission
    booking.hotel.current_business_date_record.update!(status: "audit_running")

    expect(call_service.error).to eq(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
    expect(folio.reload).to be_closed
  end

  it "rolls back the status change when audit recording fails" do
    grant_correction_permission
    allow(FinancialControls::AuditEventRecorder).to receive(:call!).and_raise("audit unavailable")

    expect(call_service.error).to eq("audit unavailable")
    expect(folio.reload).to be_closed
  end
end
