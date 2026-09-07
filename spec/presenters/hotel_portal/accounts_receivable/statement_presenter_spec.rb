# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::StatementPresenter do
  it "materializes only the selected ledger page" do
    ledger = instance_double(Reports::AccountsReceivable::GenerateStatementRecords::Ledger, count: 55)
    allow(ledger).to receive(:page).with(offset: 50, limit: 50).and_return(%w[row-51 row-55])
    allow(ledger).to receive(:all)
    report = double("StatementReport", ledger: ledger)
    request = { base_url: "http://test.host", path: "/hotel/1/accounts-receivable/statements/1", params: { "page" => 2 } }

    presenter = described_class.new(report:, params: { page: 2 }, request:)

    expect(presenter.paginated_rows).to eq(%w[row-51 row-55])
    expect(presenter.pagination).to have_attributes(count: 55, page: 2, pages: 2)
    expect(ledger).not_to have_received(:all)
  end
end
