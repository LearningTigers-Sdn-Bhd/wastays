require 'rails_helper'

RSpec.describe 'Public::Sessions', type: :request do
  describe 'POST /login' do
    let(:account) { create(:account, status: 'suspended') }
    let(:user) { create(:user, account: account, password: 'password123', password_confirmation: 'password123') }

    it 'rejects login for suspended accounts' do
      post login_path, params: { email: user.email, password: 'password123' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Your account has been suspended. Please contact support.')
    end
  end
end
