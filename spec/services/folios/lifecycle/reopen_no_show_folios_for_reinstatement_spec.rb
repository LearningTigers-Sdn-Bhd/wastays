# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::ReopenNoShowFoliosForReinstatement do
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

  # The reopen authorization is granted and withdrawn per folio, so a booking
  # with several lifecycle-closed folios must reopen every one of them — a
  # withdrawal after the first would leave the rest blocked by the guard.
  it "reopens every lifecycle-closed folio on the booking" do
    folios = [
      create(:booking_folio, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current),
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current),
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current)
    ]
    folios.each do |folio|
      create(
        :folio_operation_log,
        hotel: hotel,
        booking: booking,
        operation_type: "close_folio",
        source_folio: folio,
        target_folio: folio,
        metadata: { source: "no_show_finalization" }
      )
    end

    described_class.call(booking: booking, user: user)

    expect(folios.map { |folio| folio.reload.status }).to all(eq("open"))
    expect(folios.map { |folio| folio.reload.closed_at }).to all(be_nil)
    expect(FolioOperationLog.where(operation_type: "reopen_folio", source_folio: folios).count).to eq(3)
  end
end
