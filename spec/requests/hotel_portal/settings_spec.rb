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
    it 'updates check-in notification settings and channels' do
      patch hotel_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '1',
          channels: [ 'whatsapp', 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')

      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'check_in_confirmation')
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
    end

    it 'allows disabling check-in notification while keeping selected channels' do
      NotificationConfig.create!(
        hotel: hotel,
        notification_type: 'check_in_confirmation',
        enabled: true,
        channels: %w[whatsapp],
        settings: {}
      )

      patch hotel_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '0',
          channels: [ 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'check_in_confirmation')
      expect(config.enabled).to be(false)
      expect(config.channels).to eq([ 'email' ])
    end

    it 'updates post-stay review request settings' do
      patch hotel_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          notification_type: 'post_stay_review_request',
          enabled: '1',
          channels: [ 'whatsapp', 'email' ],
          settings: {
            review_link: 'https://g.page/r/sample/review',
            send_delay_hours: '4'
          }
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'post_stay_review_request')
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings['review_link']).to eq('https://g.page/r/sample/review')
      expect(config.settings['send_delay_hours']).to eq(4)
    end

    it "updates pre-arrival notification settings with channels and stages" do
      patch hotel_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "pre_arrival_notification",
          enabled: "1",
          channels: [ "whatsapp", "email" ],
          settings: {
            stages: [ "d2", "d1" ]
          }
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "pre_arrival_notification")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings["stages"]).to eq(%w[d2 d1])
    end

    it "updates check-out receipt message settings with both channels" do
      patch hotel_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "check_out_receipt_message",
          enabled: "1",
          channels: [ "whatsapp", "email" ]
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "check_out_receipt_message")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
    end

    it "updates in-stay guest messaging settings with rules and quiet hours" do
      patch hotel_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "in_stay_guest_messaging",
          enabled: "1",
          channels: [ "whatsapp", "email" ],
          settings: {
            rules: {
              mid_stay: { enabled: "1", time: "12:00" },
              upsell: { enabled: "1", time: "17:00" },
              activity: { enabled: "0", time: "10:00" }
            },
            quiet_hours: {
              enabled: "1",
              start: "22:00",
              end: "08:00"
            }
          }
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "in_stay_guest_messaging")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings.dig("rules", "mid_stay", "enabled")).to be(true)
      expect(config.settings.dig("rules", "activity", "enabled")).to be(false)
      expect(config.settings.dig("quiet_hours", "start")).to eq("22:00")
      expect(config.settings.dig("quiet_hours", "end")).to eq("08:00")
    end

    it 'ignores tampered status params and updates allowed banking details' do
      patch hotel_settings_path(hotel), params: {
        account: {
          status: 'suspended',
          banking_detail_attributes: {
            account_holder_name: 'Syarikat Maju Jaya Sdn Bhd',
            bank_name: 'Maybank',
            account_number: '5142 1234 5678'
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
    end

    it 'rolls back hotel settings when property policy validation fails' do
      hotel.update!(default_currency: 'MYR', tourism_tax_enabled: false, tourism_tax_amount: 10.0)
      create(:property_policy, hotel: hotel, check_in_time: '2:00 PM', check_out_time: '11:00 AM')

      patch hotel_settings_path(hotel), params: {
        hotel: {
          default_currency: 'USD',
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
      expect(hotel.tourism_tax_enabled?).to be(false)
      expect(hotel.tourism_tax_amount).to eq(10.0)

      property_policy = hotel.property_policy.reload
      expect(property_policy.check_in_time).to eq('2:00 PM')
      expect(property_policy.check_out_time).to eq('11:00 AM')
    end

    it 'does not allow hotel users to update payment gateway configuration' do
      patch hotel_settings_path(hotel), params: {
        payment_setting: {
          gateway: 'razorpay',
          api_key: 'rzp_test_key',
          secret_key: 'rzp_test_secret',
          webhook_secret: 'whsec_test',
          status: 'active'
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Payment gateway credentials are managed by superadmin.')
      expect(hotel.payment_settings.find_by(gateway: 'razorpay')).to be_nil
    end

    it 'updates ai concierge tone and provider configuration' do
      patch hotel_settings_path(hotel), params: {
        form_id: 'ai_configuration',
        hotel: {
          ai_provider_enabled: '1',
          ai_concierge_tone: 'cheerful',
          ai_provider_name: 'openai',
          ai_provider_key: 'test-api-key'
        }
      }

      expect(response).to redirect_to(hotel_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')

      hotel.reload
      expect(hotel.ai_provider_enabled).to be(true)
      expect(hotel.ai_concierge_tone).to eq('cheerful')
      expect(hotel.ai_provider_name).to eq('openai')
    end
  end
end
