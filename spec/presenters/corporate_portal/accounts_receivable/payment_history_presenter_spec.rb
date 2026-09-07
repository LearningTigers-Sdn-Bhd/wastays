# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AccountsReceivable::PaymentHistoryPresenter do
  let(:account) { create(:account, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: account) }

  it "hydrates only the records on the selected page" do
    payments = Array.new(26) do |index|
      create(
        :ar_payment,
        hotel_corporate_account: relationship,
        hotel: relationship.hotel,
        reference_number: "HYDRATE-#{index}",
        received_at: Date.new(2026, 8, 1) + index.days
      )
    end
    presenter = described_class.new(
      account: account,
      params: { page: 2 },
      request: request_context(page: 2)
    )
    instantiated = Hash.new(0)
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      instantiated[payload[:class_name]] += payload[:record_count]
    end

    rows = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") { presenter.rows }

    expect(rows.map(&:reference)).to eq([ payments.first.reference_number ])
    expect(presenter.pagination).to have_attributes(count: 26, page: 2, pages: 2)
    expect(instantiated["ArPayment"]).to eq(1)
  end

  private

  def request_context(params)
    {
      base_url: "http://test.host",
      path: "/corporate/ar/payments",
      params: params.stringify_keys
    }
  end
end
