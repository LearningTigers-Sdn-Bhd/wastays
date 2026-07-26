# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingWorkspaces::CreateFolioWindow do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |record| record.name = "Manage Folio Windows" } }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << permission
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
  end

  it "creates a non-primary guest folio for a guest billing party" do
    party = create(:booking_guest, booking: booking).booking_billing_party

    result = described_class.call(booking: booking, user: user, attributes: { booking_billing_party_id: party.id, label: "Incidentals Folio" })

    expect(result).to be_success
    expect(result.folio).to have_attributes(
      booking_billing_party: party,
      label: "Incidentals Folio",
      folio_type: "guest",
      payer_type: "guest",
      is_primary: false
    )
  end

  it "creates a non-primary company folio for a company billing party" do
    party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)

    result = described_class.call(booking: booking, user: user, attributes: { booking_billing_party_id: party.id })

    expect(result).to be_success
    expect(result.folio).to have_attributes(
      booking_billing_party: party,
      hotel_corporate_account: party.hotel_corporate_account,
      folio_type: "external",
      payer_type: "company",
      is_primary: false
    )
  end

  it "does not create or update routing rules" do
    party = create(:booking_guest, booking: booking).booking_billing_party

    expect do
      described_class.call(booking: booking, user: user, attributes: { booking_billing_party_id: party.id })
    end.not_to change(FolioRoutingRule, :count)
  end

  it "rejects foreign billing parties" do
    foreign_party = create(:booking_guest).booking_billing_party

    result = described_class.call(booking: booking, user: user, attributes: { booking_billing_party_id: foreign_party.id })

    expect(result).not_to be_success
    expect(result.error).to eq("Select an active billing party for this booking.")
  end

  it "rejects archived billing parties" do
    party = create(:booking_guest, booking: booking).booking_billing_party
    party.update!(archived_at: 1.day.ago)

    result = described_class.call(booking: booking, user: user, attributes: { booking_billing_party_id: party.id })

    expect(result).not_to be_success
    expect(result.error).to eq("Select an active billing party for this booking.")
  end
end
