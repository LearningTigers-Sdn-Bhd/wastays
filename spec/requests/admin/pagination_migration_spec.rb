# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin pagination migration", type: :request do
  let(:account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account:) }

  before { sign_in_as(superadmin) }

  it "paginates the payout summary array with Pagy" do
    hotel = create(:hotel)
    summaries = Array.new(26) { { hotel: hotel, booking_count: 1, total_net: 100 } }
    allow(Booking).to receive(:payout_summary_by_hotel).and_return(summaries)

    get admin_payouts_path, params: { page: 2 }

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('nav.panel-pagination [aria-current="page"]').text).to eq("2")
  end

  it "keeps the pending and paid payout-batch pages independent" do
    hotel = create(:hotel)
    create_list(:payout_batch, 26, hotel:, status: "pending", period_end: Date.current)
    create_list(
      :payout_batch,
      26,
      hotel:,
      status: "paid",
      period_end: Date.current,
      payout_at: Time.current
    )

    get admin_payout_batches_path,
      params: { date_preset: "all_time", pending_page: 2, paid_page: 2, tab: "paid" }

    document = Nokogiri::HTML(response.body)
    pending_navigation = document.at_css('nav[aria-label="Pending settlement pages"]')
    paid_navigation = document.at_css('nav[aria-label="Paid settlement pages"]')

    expect(response).to have_http_status(:ok)
    expect(pending_navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("paid_page=2", "tab=paid")
    expect(paid_navigation.at_css('a[aria-label="Previous page"]')["href"]).to include("pending_page=2", "tab=paid")
  end
end
