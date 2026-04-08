require 'rails_helper'

RSpec.describe 'Admin::Hotels', type: :request do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    sign_in_as(superadmin)
    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
  end

  describe 'GET /admin/hotels/new' do
    it 'shows account credential fields instead of account assignment' do
      get new_admin_hotel_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Account Credentials')
      expect(response.body).to include('Company / Group Name')
      expect(response.body).to include('Owner Full Name')
      expect(response.body).to include('Account Email')
      expect(response.body).to include('Default Password')
      expect(response.body).not_to include('Status')
      expect(response.body).not_to include('Assign to Account')
    end
  end

  describe 'POST /admin/hotels' do
    let(:hotel_params) do
      {
        account: {
          name: 'Luma Hospitality Group'
        },
        hotel: {
          name: 'Luma Stay',
          address: '1 Jalan Ampang',
          city: 'Kuala Lumpur',
          country: 'Malaysia',
          star_rating: 4
        },
        user: {
          name: 'Hotel Owner',
          email: 'owner@lumastay.test'
        }
      }
    end

    it 'creates a dedicated account and user for the hotel' do
      expect {
        post admin_hotels_path, params: hotel_params
      }.to change(Account, :count).by(1)
        .and change(User, :count).by(1)
        .and change(Hotel, :count).by(1)

      hotel = Hotel.order(:created_at).last
      user = User.find_by!(email: 'owner@lumastay.test')

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(hotel.account).to eq(user.account)
      expect(hotel.account.name).to eq('Luma Hospitality Group')
      expect(hotel.name).to eq('Luma Stay')
      expect(hotel.status).to eq('approved')
      expect(user.authenticate(HotelOps::CreateHotel::DEFAULT_PASSWORD)).to eq(user)
    end
  end

  describe 'GET /admin/hotels/:id' do
    let(:account) { create(:account, name: 'Luma Hospitality Group', status: 'active') }
    let(:hotel) { create(:hotel, account: account, name: 'Luma Stay', status: 'approved') }
    let!(:owner) { create(:user, :admin, account: account, name: 'Rose Yeo', email: 'rose@luma.test') }
    let!(:banking_detail) do
      create(
        :banking_detail,
        account: account,
        account_holder_name: 'Rose Yeo',
        bank_name: 'Maybank',
        account_number: '5142 1234 5678',
        account_type: 'current'
      )
    end
    let!(:global_margin_rule) { create(:margin_rule, settable: nil, rate: 12.0, status: 'active') }
    let!(:staff) { create(:user, account: account, name: 'Ken Tan', email: 'ken@luma.test') }
    let!(:current_month_booking) do
      create(
        :booking,
        hotel: hotel,
        status: 'confirmed',
        total_amount: 500.0,
        margin_amount: 50.0,
        net_amount: 450.0,
        margin_rate: 10.0,
        created_at: Time.current.beginning_of_month + 2.days
      )
    end
    let!(:second_current_month_booking) do
      create(
        :booking,
        hotel: hotel,
        status: 'completed',
        total_amount: 300.0,
        margin_amount: 45.0,
        net_amount: 255.0,
        margin_rate: 15.0,
        created_at: Time.current.beginning_of_month + 5.days
      )
    end
    let!(:previous_month_booking) do
      create(
        :booking,
        hotel: hotel,
        status: 'confirmed',
        total_amount: 900.0,
        margin_amount: 90.0,
        net_amount: 810.0,
        margin_rate: 10.0,
        created_at: 1.month.ago.beginning_of_month + 1.day
      )
    end

    it 'shows account details separately from account users' do
      get admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Back to Hotels')
      expect(response.body).to include('Review hotel details, account ownership, and current operating performance before taking action.')
      expect(response.body).to include('Suspend')
      expect(response.body).not_to include('Suspend Hotel')
      expect(response.body).to include('Account Information')
      expect(response.body).to include('Luma Hospitality Group')
      expect(response.body).to include('Active')
      expect(response.body).to include('Account Users')
      expect(response.body).to include('Rose Yeo')
      expect(response.body).to include('rose@luma.test')
      expect(response.body).to include('Admin')
      expect(response.body).to include('Ken Tan')
      expect(response.body).to include('ken@luma.test')
      expect(response.body).to include('Hotel Staff')
      expect(response.body).to include('Banking Details')
      expect(response.body).to include('Rose Yeo')
      expect(response.body).to include('Maybank')
      expect(response.body).to include('5142 1234 5678')
      expect(response.body).to include('Current')
      expect(response.body).to include('Gross Revenue This Month')
      expect(response.body).to include('RM 800.00')
      expect(response.body).to include('WAStays Earned Margin This Month')
      expect(response.body).to include('RM 95.00')
      expect(response.body).to include('Hotel Net Earnings This Month')
      expect(response.body).to include('RM 705.00')
      expect(response.body).to include('Bookings This Month')
      expect(response.body).to include('2')
      expect(response.body).to include('Configured Margin Rate')
      expect(response.body).to include('12.00%')
      expect(response.body).not_to include('Realized Margin Rate')
    end
  end

  describe 'GET /admin/hotels/:id/edit' do
    let(:hotel) { create(:hotel, status: 'approved') }

    it 'hides the status field from the hotel edit form' do
      get edit_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Status')
      expect(response.body).not_to include('hotel[status]')
    end
  end

  describe 'POST /admin/hotels/:id/suspend' do
    let(:account) { create(:account, status: 'active') }
    let(:hotel) { create(:hotel, account: account, status: 'approved') }

    it 'suspends both the hotel and its account' do
      post suspend_admin_hotel_path(hotel)

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(flash[:notice]).to eq('Account and hotel have been suspended.')
      expect(hotel.reload.status).to eq('suspended')
      expect(account.reload.status).to eq('suspended')
    end
  end

  describe 'POST /admin/hotels/:id/approve' do
    let(:account) { create(:account, status: 'suspended') }
    let(:hotel) { create(:hotel, account: account, status: 'suspended') }

    it 'reactivates both the hotel and its account' do
      post approve_admin_hotel_path(hotel)

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(flash[:notice]).to eq('Account and hotel have been reactivated.')
      expect(hotel.reload.status).to eq('approved')
      expect(account.reload.status).to eq('active')
    end
  end
end
