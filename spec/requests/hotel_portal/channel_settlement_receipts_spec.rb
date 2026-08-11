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
    expect(document.at_css("#hotel-breadcrumb").text.squish).to eq("Financial OTA Settlements Record Receipt")
    expect(document.at_css("button.panel-button svg")).to be_present
    footer = document.at_css("form footer")
    expect(footer).to be_present
    expect(footer["class"]).to include("border-t")
    expect(footer.text.squish).to include("The receipt is posted only after its full amount is allocated.")
  end

  it "links hotel profile managers to Payment Methods when receipt setup is incomplete" do
    profile_permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end
    role.permissions << profile_permission

    get new_hotel_channel_settlement_receipt_path(hotel)

    page = Capybara.string(response.body)
    expect(page).to have_text("Add a receiving payment method")
    expect(page).to have_text("Hotel Settings → Payment Methods")
    expect(page).to have_link("Open Payment Methods", href: hotel_payment_methods_path(hotel))
  end

  it "explains when there are no outstanding settlements" do
    allocation.destroy!

    get new_hotel_channel_settlement_receipt_path(hotel)

    page = Capybara.string(response.body)
    expect(page).to have_text("No outstanding OTA settlements")
    expect(page).to have_text("A receipt can be recorded after an OTA booking creates an expected settlement balance.")
    expect(page).to have_link("View OTA reconciliation", href: channel_settlements_hotel_reports_path(hotel))
  end

  it "defaults to an available pair and renders accessible application behavior" do
    payment_method

    get new_hotel_channel_settlement_receipt_path(hotel), params: {
      booking_source_id: "999999",
      currency: "USD"
    }

    document = Nokogiri::HTML(response.body)
    root = document.at_css('[data-controller="ota-receipt-form"]')
    source_select = document.at_css("#channel_settlement_receipt_booking_source_id")
    currency_select = document.at_css("#channel_settlement_receipt_currency")
    allocation_input = document.at_css("#allocation-#{allocation.id}")

    expect(root).to be_present
    expect(root["class"].split).not_to include("w-full")
    expect(source_select.at_css("option[selected]")["value"]).to eq(source.id.to_s)
    expect(currency_select.at_css("option[selected]")["value"]).to eq(allocation.currency)
    expect(allocation_input["name"]).to eq("allocations[#{allocation.id}]")
    expect(allocation_input["class"]).to include("panel-input")
    expect(allocation_input["aria-describedby"]).to be_nil
    expect(document.at_css('[aria-live="polite"]')).to be_present
    expect(document.at_css('[data-controller="panels-ui--date-time-picker"]')).to be_present
    expect(response.body).to include("Overpayment entered")
  end

  it "scopes allocation rows by OTA, currency, and server-side search" do
    payment_method
    usd_settlement = create(:channel_settlement,
      hotel:, booking_source: source, currency: "USD", channel_manager_reference: "USD-ONLY")
    usd_allocation = create(:channel_settlement_allocation,
      channel_settlement: usd_settlement, currency: "USD")
    other_source = create(:booking_source, kind: "ota", label: "Other OTA")
    other_settlement = create(:channel_settlement,
      hotel:, booking_source: other_source, currency: "MYR", channel_manager_reference: "OTHER-SOURCE")
    create(:channel_settlement_allocation, channel_settlement: other_settlement, currency: "MYR")

    get new_hotel_channel_settlement_receipt_path(hotel), params: {
      booking_source_id: source.id,
      currency: "USD",
      allocation_search: usd_allocation.booking.confirmation_token
    }

    expect(response.body).to include("USD-ONLY")
    expect(response.body).not_to include(settlement.channel_manager_reference)
    expect(response.body).not_to include("OTHER-SOURCE")
  end

  it "only offers receipt settlement methods and connects validation errors to controls" do
    payment_method

    post hotel_channel_settlement_receipts_path(hotel), params: {
      channel_settlement_receipt: {
        booking_source_id: source.id,
        hotel_payment_method_id: payment_method.id,
        settlement_method: "guest_card",
        amount: "",
        currency: "MYR",
        received_at: ""
      },
      allocations: {}
    }

    document = Nokogiri::HTML(response.body)
    method_values = document.css("#channel_settlement_receipt_settlement_method option").map { |option| option["value"] }
    summary = document.at_css("#receipt-error-summary")
    amount_input = document.at_css("#channel_settlement_receipt_amount")
    allocation_input = document.at_css("#allocation-#{allocation.id}")

    expect(response).to have_http_status(:unprocessable_content)
    expect(method_values.reject(&:blank?)).to contain_exactly("bank_transfer", "virtual_card")
    expect(summary["tabindex"]).to eq("-1")
    expect(summary["data-ota-receipt-form-target"]).to eq("errorSummary")
    expect(amount_input["aria-invalid"]).to eq("true")
    expect(amount_input["aria-describedby"]).to include("channel_settlement_receipt_amount-error")

    post hotel_channel_settlement_receipts_path(hotel), params: {
      channel_settlement_receipt: {
        booking_source_id: source.id,
        hotel_payment_method_id: payment_method.id,
        settlement_method: "bank_transfer",
        amount: "10.00",
        currency: "MYR",
        received_at: Time.current.iso8601
      },
      allocations: {}
    }
    allocation_input = Nokogiri::HTML(response.body).at_css("#allocation-#{allocation.id}")
    expect(allocation_input["aria-invalid"]).to eq("true")
    expect(allocation_input["aria-describedby"]).to include("allocation-#{allocation.id}-error")
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
