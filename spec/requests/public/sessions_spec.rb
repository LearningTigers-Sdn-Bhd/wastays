require 'rails_helper'

RSpec.describe 'Public::Sessions', type: :request do
  describe 'POST /login' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'password123', password_confirmation: 'password123') }

    it 'rejects login for suspended accounts' do
      account.update!(status: 'suspended')

      post login_path, params: { email: user.email, password: 'password123' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Your account has been suspended. Please contact support.')
    end

    it 'lands setup-hotel staff without onboarding permission on the setup explainer' do
      hotel = create(:hotel, account:, status: 'setup')
      role = create(:role, account:)
      create(:user_hotel_access, user:, hotel:, role:)

      post login_path, params: { email: user.email, password: 'password123' }

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
      follow_redirect!
      expect(response).to redirect_to(hotel_setup_lock_path(hotel))
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('still being set up')
    end
  end
end
