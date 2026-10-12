# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe "AR folio correction sheets", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel, status: "completed") }
  let(:account) { create(:hotel_corporate_account, :direct_bill, hotel: hotel, contact_email: "billing@example.com") }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: account, status: "open") }

  before do
    sign_in_as(user)
    create(:folio_transaction, booking_folio: folio, amount: 2000)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio, user: user, settlement_method: "direct_bill")).to be_success
  end

  it "requires a reason, opens the existing sheet, and shows the correction totals at close" do
    get hotel_folio_action_reopen_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("carry existing payments forward", "required")
    post hotel_folio_action_reopen_window_path(hotel, booking, folio), params: { booking_folio: { reason: "Wrong charge" } }
    expect(folio.reload).to be_open
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    get hotel_folio_action_close_window_path(hotel, booking, folio), headers: { "Turbo-Frame" => "folio_action_sheet" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Corrected amount", "1,800.00", "billing@example.com", "Close &amp; correct")
    post hotel_folio_action_close_window_path(hotel, booking, folio), params: { booking_folio: { send_documents: "1" } }
    expect(folio.reload).to be_closed
    expect(folio.ar_invoice.amount).to eq(1800)
    get hotel_ar_invoice_path(hotel, folio.ar_invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Original:", "Replacement:")
  end

  it "prints the cancellation credit and the preserved original invoice" do
    original = folio.ar_invoice
    expect(Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user)).to be_success
    correction = ArInvoiceCorrection.last
    get credit_hotel_ar_invoice_correction_path(hotel, correction)
    expect(response).to have_http_status(:ok)
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join(" ")
    expect(text).to include(correction.credit_reference, original.formatted_invoice_number, "2,000.00")
    get pdf_hotel_ar_invoice_path(hotel, original)
    expect(response).to have_http_status(:ok)
  end

  it "does not expose another hotel's correction" do
    other = create(:hotel, status: "live")
    expect(Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")).to be_success
    patch hotel_ar_invoice_correction_path(other, ArInvoiceCorrection.last)
    expect(response).to have_http_status(:not_found)
  end
end
