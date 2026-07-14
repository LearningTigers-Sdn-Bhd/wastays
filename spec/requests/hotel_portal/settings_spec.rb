require 'rails_helper'

RSpec.describe 'HotelPortal::Settings', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:hotel) { create(:hotel, account: account, status: 'registered', plan: plan) }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_account'))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    sign_in_as(user)
  end

  describe 'GET /hotel/settings with legacy hotel_id param' do
    it 'redirects to the canonical hotel-scoped path' do
      get legacy_hotel_settings_path, params: { hotel_id: hotel.id }
      follow_redirect!

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
    end
  end

  describe "GET /hotel/:hotel_id/settings" do
    it "uses the General group URL for notification settings" do
      expect(hotel_notification_settings_path(hotel)).to eq("/hotel/#{hotel.to_param}/settings/general/notifications")
    end

    it "permanently redirects the old Guest Content notification URL" do
      get "/hotel/#{hotel.to_param}/settings/guest-content/notifications"

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "permanently redirects the settings root to General" do
      get hotel_settings_path(hotel)

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "uses the active destination as the page heading" do
      {
        hotel_general_settings_path(hotel) => "General Settings",
        hotel_ai_concierge_settings_path(hotel) => "AI Concierge",
        hotel_notification_settings_path(hotel) => "Notifications",
        hotel_banking_details_settings_path(hotel) => "Banking Details"
      }.each do |path, expected_heading|
        get path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.css("h1").map { |heading| heading.text.squish }).to eq([ expected_heading ])
      end
    end

    it "shows concierge QR entry when AI concierge page is enabled" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("View QR")
    end

    it "renders the guest registration card field selection" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      grc_settings = Nokogiri::HTML(response.body).at_css("#guest-registration-card")
      expect(grc_settings["class"]).to include("rounded-2xl", "border", "bg-card")
    end

    it "shows setup tabs in the settings tab bar" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(response.body).not_to include(%(data-testid="settings-setup-shortcuts"))
    end

    it "uses the dedicated flat settings navigation and portal breadcrumbs" do
      hotel.update!(status: "approved")
      manage_users = Permission.find_or_create_by!(slug: "manage_users") { |permission| permission.name = "Manage Users" }
      RolePermission.find_or_create_by!(role: role, permission: manage_users)
      get hotel_general_settings_path(hotel)

      document = response.parsed_body
      sidebar = document.at_css("#hotel-settings-sidebar")
      expect(sidebar).to be_present
      expect(document.at_css("#hotel-sidebar")).to be_nil
      expect(sidebar["data-sidebar-mode"]).to be_nil
      items = sidebar.css(".panel-sidebar__section-items > .panel-sidebar__item")
      expect(items.map { |item| item.at_css("[data-sidebar-presentation='expanded'] .panel-sidebar__label").text.squish }).to eq(
        [ "General", "Property", "Finance", "Guest Content", "Team" ]
      )
      expect(sidebar.text).not_to include("Back to previous page")

      breadcrumb_items = document.css("#hotel-breadcrumb .breadcrumb-item")
      expect(breadcrumb_items[0].at_css("a")&.text&.squish).to eq("Hotel Portal")
      expect(breadcrumb_items[0].at_css("button[aria-label='Open Hotel Portal navigation']")).to be_nil
      expect(breadcrumb_items[1].at_css("a")&.text&.squish).to eq("Settings")
      expect(breadcrumb_items[2].text.squish).to eq("General")
      expect(breadcrumb_items[2].at_css("a, button")).to be_nil
      expect(breadcrumb_items[3].at_css("a")&.text&.squish).to eq("General Settings")
      expect(breadcrumb_items[3].at_css("button[aria-label='Open General Settings navigation']")).to be_present
      expect(breadcrumb_items[3].css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "General Settings", "Rate Settings", "Notifications", "Plan & Billing" ]
      )
    end

    it "uses permission-filtered tabs in the active settings breadcrumb menu" do
      get hotel_banking_details_settings_path(hotel)

      breadcrumb_items = response.parsed_body.css("#hotel-breadcrumb .breadcrumb-item")
      expect(breadcrumb_items[2].text.squish).to eq("Finance")
      expect(breadcrumb_items[2].at_css("a, button")).to be_nil
      expect(breadcrumb_items[3].at_css("button[aria-label='Open Banking Details navigation']")).to be_present
      expect(breadcrumb_items[3].css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "Banking Details", "Taxes & Fees", "Transaction Codes" ]
      )
    end

    it "places the admin portal destination in the footer for superadmins" do
      hotel.update!(status: "approved")
      sign_in_as(create(:user, :superadmin, account: account))

      get hotel_general_settings_path(hotel)

      footer_link = response.parsed_body.at_css("#hotel-settings-sidebar .panel-sidebar__footer a[href='#{admin_dashboard_path}']")
      expect(footer_link.text.squish).to eq("Go to Admin Portal")
      expect(footer_link["target"]).to eq("_blank")
      expect(footer_link["rel"]).to eq("noopener noreferrer")
    end

    it "does not expose resource-owned pages as settings panels" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(data-tab-name="hotel_details"))
      expect(response.body).not_to include(%(data-tab-name="taxes_fees"))
      expect(response.body).not_to include(%(data-testid="settings-hotel-details-panel"))
      expect(response.body).not_to include(%(data-testid="settings-taxes-fees-panel"))
    end

    it "redirects legacy tab URLs to canonical resource paths" do
      get hotel_settings_path(hotel, tab: "general")
      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "ai")
      expect(response).to redirect_to(hotel_ai_concierge_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "notifications")
      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "banking")
      expect(response).to redirect_to(hotel_banking_details_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "hotel_details")
      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "taxes_fees")
      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "hides concierge QR entry when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("View QR Code")
      expect(response.body).not_to include("Concierge Pages")
    end
  end

  describe "GET /hotel/:hotel_id/concierge_qr" do
    it "redirects when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_concierge_qr_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
    end
  end

  describe 'PATCH /hotel/settings' do
    it "updates guest registration card fields" do
      patch hotel_general_settings_path(hotel), params: {
        form_id: "hotel_settings",
        hotel: { guest_registration_card_fields: %w[phone room_type check_in] }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(hotel.reload.guest_registration_card_fields).to eq(%w[phone room_type check_in])
    end

    it "discards unknown guest registration card fields and allows none" do
      patch hotel_general_settings_path(hotel), params: {
        form_id: "hotel_settings",
        hotel: { guest_registration_card_fields: [ "", "unknown" ] }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(hotel.reload.guest_registration_card_fields).to eq([])
    end

    it 'updates check-in notification settings and channels' do
      patch hotel_general_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '1',
          channels: [ 'whatsapp', 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
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

      patch hotel_notification_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '0',
          channels: [ 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'check_in_confirmation')
      expect(config.enabled).to be(false)
      expect(config.channels).to eq([ 'email' ])
    end

    it 'updates post-stay review request settings' do
      patch hotel_notification_settings_path(hotel), params: {
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

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'post_stay_review_request')
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings['review_link']).to eq('https://g.page/r/sample/review')
      expect(config.settings['send_delay_hours']).to eq(4)
    end

    it "updates pre-arrival notification settings with channels and stages" do
      patch hotel_notification_settings_path(hotel), params: {
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

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "pre_arrival_notification")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings["stages"]).to eq(%w[d2 d1])
    end

    it "updates check-out receipt message settings with both channels" do
      patch hotel_notification_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "check_out_receipt_message",
          enabled: "1",
          channels: [ "whatsapp", "email" ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "check_out_receipt_message")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
    end

    it "updates in-stay guest messaging settings with rules and quiet hours" do
      patch hotel_notification_settings_path(hotel), params: {
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

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "in_stay_guest_messaging")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings.dig("rules", "mid_stay", "enabled")).to be(true)
      expect(config.settings.dig("rules", "activity", "enabled")).to be(false)
      expect(config.settings.dig("quiet_hours", "start")).to eq("22:00")
      expect(config.settings.dig("quiet_hours", "end")).to eq("08:00")
    end

    it 'ignores tampered status params and updates allowed banking details' do
      patch hotel_banking_details_settings_path(hotel), params: {
        account: {
          status: 'suspended',
          banking_detail_attributes: {
            account_holder_name: 'Syarikat Maju Jaya Sdn Bhd',
            bank_name: 'Maybank',
            account_number: '5142 1234 5678'
          }
        }
      }

      expect(response).to redirect_to(hotel_banking_details_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')
      expect(hotel.reload.status).to eq('registered')
      banking_detail = account.reload.banking_detail
      expect(banking_detail.account_holder_name).to eq('Syarikat Maju Jaya Sdn Bhd')
      expect(banking_detail.bank_name).to eq('Maybank')
      expect(banking_detail.account_number).to eq('5142 1234 5678')
    end

    it 'rolls back hotel settings when property policy validation fails' do
      hotel.update!(default_currency: 'MYR')
      create(:property_policy, hotel: hotel, check_in_time: '2:00 PM', check_out_time: '11:00 AM')

      patch hotel_general_settings_path(hotel), params: {
        hotel: {
          default_currency: 'USD',
          property_policy_attributes: {
            check_in_time: '3:00 PM',
            check_out_time: ''
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      breadcrumb = response.parsed_body.at_css("#hotel-breadcrumb")
      items = breadcrumb.css(".breadcrumb-item")
      expect(items[0].at_css("a")&.text&.squish).to eq("Hotel Portal")
      expect(items[1].at_css("a")&.text&.squish).to eq("Settings")
      expect(items[2].text.squish).to eq("General")
      expect(items[2].at_css("a, button")).to be_nil
      expect(items[3].at_css("button[aria-label='Open General Settings navigation']")).to be_present

      hotel.reload
      expect(hotel.default_currency).to eq('MYR')

      property_policy = hotel.property_policy.reload
      expect(property_policy.check_in_time).to eq('2:00 PM')
      expect(property_policy.check_out_time).to eq('11:00 AM')
    end

    it 'does not allow hotel users to update payment gateway configuration' do
      patch hotel_general_settings_path(hotel), params: {
        payment_setting: {
          gateway: 'razorpay',
          api_key: 'rzp_test_key',
          secret_key: 'rzp_test_secret',
          webhook_secret: 'whsec_test',
          status: 'active'
        }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Payment gateway credentials are managed by superadmin.')
      expect(hotel.payment_settings.find_by(gateway: 'razorpay')).to be_nil
    end

    it 'updates ai concierge tone and provider configuration' do
      patch hotel_ai_concierge_settings_path(hotel), params: {
        form_id: 'ai_configuration',
        hotel: {
          ai_provider_enabled: '1',
          ai_concierge_tone: 'cheerful',
          ai_provider_name: 'openai',
          ai_provider_key: 'test-api-key'
        }
      }

      expect(response).to redirect_to(hotel_ai_concierge_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')

      hotel.reload
      expect(hotel.ai_provider_enabled).to be(true)
      expect(hotel.ai_concierge_tone).to eq('cheerful')
      expect(hotel.ai_provider_name).to eq('openai')
    end
  end
end
