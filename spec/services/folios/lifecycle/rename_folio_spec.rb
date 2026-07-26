# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::RenameFolio do
  let(:booking) { create(:booking, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel) }

  it "renames open folios and records an operation log" do
    result = described_class.call(folio: folio, user: user, name: "ABC Sdn Bhd", reason: "Company billing")

    expect(result).to be_success
    expect(folio.reload.name).to eq("ABC Sdn Bhd")
    expect(FolioOperationLog.last).to have_attributes(operation_type: "rename_folio", reason: "Company billing")
  end
end
