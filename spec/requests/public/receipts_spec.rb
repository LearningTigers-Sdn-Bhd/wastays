# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public payment receipts", type: :request do
  it "serves an individual payment receipt through its opaque access token" do
    receipt = create(:deposit, :prepayment).receipt

    get receipt_path(receipt.access_token)

    expect(response).to have_http_status(:success)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers.fetch("Content-Disposition")).to include(receipt.public_number)
  end

  it "does not expose receipts by their sequential public number" do
    receipt = create(:deposit, :prepayment).receipt

    get receipt_path(receipt.public_number)

    expect(response).to have_http_status(:not_found)
  end
end
