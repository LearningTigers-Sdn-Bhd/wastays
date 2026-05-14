require 'rails_helper'

RSpec.describe 'Admin::ExchangeRates', type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    sign_in_as(superadmin)
  end

  it 'renders the exchange rates page' do
    get admin_exchange_rates_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Exchange Rates')
    expect(response.body).to include('Conversion Rate')
  end

  it 'creates a managed exchange rate' do
    expect do
      post admin_exchange_rates_path, params: {
        exchange_rate: {
          base_currency: 'USD',
          currency_code: 'MYR',
          rate: '4.75',
          effective_at: Time.current,
          source: 'manual',
          active: '1'
        }
      }
    end.to change(ExchangeRate, :count).by(1)

    rate = ExchangeRate.find_by!(base_currency: 'USD', currency_code: 'MYR')
    expect(response).to redirect_to(admin_exchange_rates_path)
    expect(rate.rate).to eq(4.75)
    expect(rate.created_by).to eq(superadmin)
  end

  it 'rejects invalid ISO currency codes' do
    expect do
      post admin_exchange_rates_path, params: {
        exchange_rate: {
          base_currency: 'USD',
          currency_code: 'ZZZ',
          rate: '4.75',
          effective_at: Time.current,
          source: 'manual',
          active: '1'
        }
      }
    end.not_to change(ExchangeRate, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
