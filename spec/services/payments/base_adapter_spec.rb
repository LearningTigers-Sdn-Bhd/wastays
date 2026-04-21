require "rails_helper"

RSpec.describe Payments::BaseAdapter do
  subject(:adapter) { described_class.new }

  it "raises for create_checkout_session" do
    expect {
      adapter.create_checkout_session(amount: 1, currency: "MYR", description: "x", metadata: {}, callback_url: "/")
    }.to raise_error(NotImplementedError)
  end

  it "raises for verify_client_callback" do
    expect {
      adapter.verify_client_callback(payment_response: {})
    }.to raise_error(NotImplementedError)
  end

  it "raises for verify_webhook" do
    expect {
      adapter.verify_webhook(payload: "{}", signature: "sig")
    }.to raise_error(NotImplementedError)
  end

  it "raises for handle_webhook" do
    expect {
      adapter.handle_webhook(payload: {})
    }.to raise_error(NotImplementedError)
  end
end
