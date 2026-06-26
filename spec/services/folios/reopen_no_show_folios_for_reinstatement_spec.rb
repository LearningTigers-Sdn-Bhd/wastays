# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ReopenNoShowFoliosForReinstatement do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "no_show") }

  it "reopens only folios closed by no-show finalization" do
    lifecycle_folio = create(:booking_folio, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current)
    manual_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current)
    create(
      :folio_operation_log,
      hotel: hotel,
      booking: booking,
      operation_type: "close_folio",
      source_folio: lifecycle_folio,
      target_folio: lifecycle_folio,
      metadata: { source: "no_show_finalization" }
    )
    create(
      :folio_operation_log,
      hotel: hotel,
      booking: booking,
      operation_type: "close_folio",
      source_folio: manual_folio,
      target_folio: manual_folio,
      metadata: { source: "staff" }
    )

    described_class.call(booking: booking, user: user)

    expect(lifecycle_folio.reload).to be_open
    expect(manual_folio.reload).to be_closed
    expect(
      FolioOperationLog.where(
        operation_type: "reopen_folio",
        source_folio: lifecycle_folio
      ).sole.metadata["source"]
    ).to eq("no_show_reinstatement")
  end
end
