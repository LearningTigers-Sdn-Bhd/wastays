require 'rails_helper'

RSpec.describe DisplayCurrencyResolver do
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: '203.0.113.10') }
  let(:cookies) { {} }

  before do
    create(:exchange_rate, currency_code: 'USD', rate_to_myr: 4.0)
    allow_any_instance_of(described_class).to receive(:country_code_from_ip).and_return(nil)
  end

  it 'uses query override and persists it' do
    result = described_class.new(params: { display_currency: 'USD' }, cookies: cookies, request: request).call

    expect(result).to eq('USD')
    expect(cookies[:display_currency][:value]).to eq('USD')
  end

  it 'uses persisted user choice' do
    expect(described_class.new(params: {}, cookies: { display_currency: 'USD' }, request: request).call).to eq('USD')
  end

  it 'falls back to MYR for unknown or unavailable currencies' do
    expect(described_class.new(params: { display_currency: 'AUD' }, cookies: cookies, request: request).call).to eq('MYR')
  end

  it 'resolves US geolocation to USD when an active rate exists' do
    allow_any_instance_of(described_class).to receive(:country_code_from_ip).and_return('US')

    expect(described_class.new(params: {}, cookies: cookies, request: request).call).to eq('USD')
  end
end
