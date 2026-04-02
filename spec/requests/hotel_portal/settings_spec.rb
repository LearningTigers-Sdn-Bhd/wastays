require 'rails_helper'

RSpec.describe 'HotelPortal::Settings', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'registered') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_account'))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe 'GET /hotel/settings with legacy hotel_id param' do
    it 'redirects to the canonical hotel-scoped path' do
      get legacy_hotel_settings_path, params: { hotel_id: hotel.id }

      expect(response).to redirect_to(hotel_settings_path(hotel))
    end
  end

  describe 'PATCH /hotel/settings' do
    it 'ignores tampered status params and updates allowed banking details' do
      patch hotel_settings_path(hotel), params: {
        account: {
          status: 'suspended',
          banking_detail_attributes: {
            account_holder_name: 'Syarikat Maju Jaya Sdn Bhd',
            bank_name: 'Maybank',
            account_number: '5142 1234 5678',
            account_type: 'current'
          }
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')
      expect(hotel.reload.status).to eq('registered')
      banking_detail = account.reload.banking_detail
      expect(banking_detail.account_holder_name).to eq('Syarikat Maju Jaya Sdn Bhd')
      expect(banking_detail.bank_name).to eq('Maybank')
      expect(banking_detail.account_number).to eq('5142 1234 5678')
      expect(banking_detail.account_type).to eq('current')
    end

    it 'rolls back hotel settings when property policy validation fails' do
      hotel.update!(default_currency: 'MYR', usd_conversion_rate: 4.5, tourism_tax_enabled: false, tourism_tax_amount: 10.0)
      create(:property_policy, hotel: hotel, check_in_time: '2:00 PM', check_out_time: '11:00 AM')

      patch hotel_settings_path(hotel), params: {
        hotel: {
          default_currency: 'USD',
          usd_conversion_rate: '4.25',
          tourism_tax_enabled: '1',
          tourism_tax_amount: '12.0',
          property_policy_attributes: {
            check_in_time: '3:00 PM',
            check_out_time: ''
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)

      hotel.reload
      expect(hotel.default_currency).to eq('MYR')
      expect(hotel.usd_conversion_rate).to eq(4.5)
      expect(hotel.tourism_tax_enabled?).to be(false)
      expect(hotel.tourism_tax_amount).to eq(10.0)

      property_policy = hotel.property_policy.reload
      expect(property_policy.check_in_time).to eq('2:00 PM')
      expect(property_policy.check_out_time).to eq('11:00 AM')
    end
  end
end
