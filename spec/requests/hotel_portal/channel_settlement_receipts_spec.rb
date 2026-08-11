# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ChannelSettlementReceipts", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:permission) do
    Permission.find_or_create_by!(slug: "manage_ar_payments") { |record| record.name = "Manage AR Payments" }
  end
  let(:view_reports) do
    Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View Reports" }
  end
  let(:source) { create(:booking_source, kind: "ota", label: "Booking Test") }
  let(:payment_method) { create(:hotel_payment_method, hotel:) }
  let(:settlement) { create(:channel_settlement, hotel:, booking_source: source) }
  let!(:allocation) { create(:channel_settlement_allocation, channel_settlement: settlement) }

  before do
    role.permissions << [ permission, view_reports ]
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the dedicated recording page with styled selection controls" do
    payment_method

    get new_hotel_channel_settlement_receipt_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Record OTA settlement receipt")
    expect(response.body).to include("Booking Test")
    expect(response.body).to include(settlement.channel_manager_reference)
    expect(response.body).to include('data-controller="panels-ui--select-menu"')
    page = Capybara.string(response.body)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#hotel-breadcrumb").text.squish).to eq("Financial Reports OTA Settlements Record Receipt")
    expect(document.at_css("button.panel-button svg")).to be_present
  end

  it "records and allocates a receipt, then returns to reconciliation" do
    expect {
      post hotel_channel_settlement_receipts_path(hotel), params: {
        channel_settlement_receipt: {
          booking_source_id: source.id,
          hotel_payment_method_id: payment_method.id,
          settlement_method: "bank_transfer",
          amount: "50.00",
          currency: "MYR",
          received_at: Time.current.iso8601,
          external_reference: "REQUEST-OTA-1"
        },
        allocations: { allocation.id.to_s => "50.00" }
      }
    }.to change(hotel.channel_settlement_receipts, :count).by(1)
      .and change(ChannelSettlementReceiptAllocation, :count).by(1)

    expect(response).to redirect_to(channel_settlements_hotel_reports_path(hotel))
  end

  it "does not allow allocations from another hotel" do
    other_allocation = create(:channel_settlement_allocation,
      channel_settlement: create(:channel_settlement, hotel: other_hotel))

    expect {
      post hotel_channel_settlement_receipts_path(hotel), params: {
        channel_settlement_receipt: {
          booking_source_id: source.id,
          hotel_payment_method_id: payment_method.id,
          settlement_method: "bank_transfer",
          amount: "10.00",
          currency: "MYR",
          received_at: Time.current.iso8601
        },
        allocations: { other_allocation.id.to_s => "10.00" }
      }
    }.not_to change(ChannelSettlementReceipt, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end


  it "links the reconciliation report to the recording workflow" do
    get channel_settlements_hotel_reports_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(new_hotel_channel_settlement_receipt_path(hotel))
  end

  it "requires the hotel-scoped payment management permission" do
    role.permissions.delete(permission)

    get new_hotel_channel_settlement_receipt_path(hotel)

    expect(response).to have_http_status(:redirect)
  end
end
