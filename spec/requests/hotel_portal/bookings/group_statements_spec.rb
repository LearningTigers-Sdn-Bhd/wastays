# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::GroupStatements", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_reports) { Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" } }

  before do
    role.permissions << view_reports
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_as(user)
  end

  it "returns the selected group AR statement as an inline PDF" do
    group = create(:group_booking, hotel:)
    booking = create(:booking, hotel:, group_booking: group, group_position: 1)
    relationship = create(:hotel_corporate_account, hotel:)
    folio = create(:booking_folio,
      booking:,
      hotel:,
      status: "closed",
      is_primary: false,
      folio_type: "external",
      payer_type: "company",
      hotel_corporate_account: relationship)
    invoice = create(:ar_invoice, booking_folio: folio, hotel:, hotel_corporate_account: relationship)

    post hotel_booking_group_statement_path(hotel, booking), params: { ar_invoice_ids: [ invoice.id ] }

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("inline", "group-statement")
  end

  it "redirects with the validation message when nothing is selected" do
    group = create(:group_booking, hotel:)
    booking = create(:booking, hotel:, group_booking: group)

    post hotel_booking_group_statement_path(hotel, booking)

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "documents"))
    expect(flash[:alert]).to eq("Select at least one AR invoice.")
  end
end
