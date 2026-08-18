require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin::Hotels', type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Hotels #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-hotels-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
  end

  describe 'GET /admin/hotels' do
    let!(:pending_hotel) do
      create(
        :hotel,
        name: "Pending Stay #{token}",
        status: "pending_review",
        onboarding_start_date: Date.new(2026, 4, 15),
        onboarding_end_date: Date.new(2026, 4, 20)
      )
    end
    let!(:live_hotel) { create(:hotel, name: "Live Stay #{token}", status: "live", hide_payout_reports: true) }
    let!(:next_session) do
      create(
        :onboarding_session,
        hotel: pending_hotel,
        trainer_name: "Mira Tan",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0)
      )
    end
    let!(:later_session) do
      create(
        :onboarding_session,
        hotel: pending_hotel,
        trainer_name: "Farid Osman",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 26, 14, 30)
      )
    end

    it 'renders the registry with PanelsUI components' do
      get admin_hotels_path

      document = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(document.css('.panel-metric-card')).to be_empty
      expect(document.at_css('table.panel-table')).to be_present
      expect(document.css('#hotel-status-tabs .tabs-tab').size).to eq(6)
      expect(document.css('.panel-select-menu').size).to eq(1)
      expect(document.at_css("select[name='per_page'] option[selected]").text).to eq('15')
      expect(document.css("turbo-frame#hotels_list .panel-badge[data-indicator='true']").size).to eq(2)
      expect(document.at_css("turbo-frame#hotels_list")).to be_present
      expect(document.at_css('table.panel-table').text).not_to include("Onboarding period", "Scheduled session")
      expect(document.at_css('table.panel-table').text).to include("Payout reports", "Visible", "Hidden")
      expect(response.body).not_to include('href="/admin/hotels/onboarding"')
    end


    it 'separates hotels waiting for the owner launch decision' do
      ready_hotel = create(
        :hotel,
        name: "Ready Stay #{token}",
        status: "ready_to_launch",
        onboarding_start_date: Date.new(2026, 4, 15),
        onboarding_end_date: Date.new(2026, 4, 20)
      )

      get admin_hotels_path, params: { status: 'ready_to_launch' }

      document = Nokogiri::HTML(response.body)
      table = document.at_css('table.panel-table')
      expect(table.text).to include(ready_hotel.name, 'Ready to launch', 'View launch status')
      expect(table.text).not_to include(pending_hotel.name)
      expect(document.at_css('#hotel-status-tabs-tab-ready_to_launch')['aria-current']).to eq('page')
    end

    it 'turns the pending-review filter into the onboarding queue' do
      get admin_hotels_path, params: { status: 'pending_review' }

      document = Nokogiri::HTML(response.body)
      table = document.at_css('table.panel-table')

      expect(table.text).to include(
        pending_hotel.name,
        "Onboarding period",
        "Scheduled session",
        "5 days",
        "15 Apr 2026 – 20 Apr 2026",
        "Mira Tan",
        "+1 more",
        "Review onboarding"
      )
      expect(table.text).not_to include(live_hotel.name, "Farid Osman")
      review_link = table.at_css("a[href='#{onboarding_admin_hotel_path(pending_hotel)}']")
      expect(review_link).to be_present
      expect(review_link["data-turbo-frame"]).to eq("_top")
      expect(document.at_css('#hotel-status-tabs-tab-all .tabs-tab__count').text).to eq('2')
      expect(document.at_css('#hotel-status-tabs-tab-pending_review')['aria-current']).to eq('page')
    end

    it 'shows fallback period dates and an empty scheduled-session state' do
      hotel_without_dates = create(
        :hotel,
        name: "Fallback Stay #{token}",
        status: "pending_review",
        created_at: Time.zone.local(2026, 4, 10, 12, 0)
      )

      travel_to(Time.zone.local(2026, 4, 15, 12, 0)) do
        get admin_hotels_path, params: { status: 'pending_review', q: hotel_without_dates.name }
      end

      table = Nokogiri::HTML(response.body).at_css('table.panel-table')
      expect(table.text).to include("5 days", "10 Apr 2026 – 15 Apr 2026", "Not scheduled")
    end
  end

  describe 'GET /admin/hotels/new' do
    it 'renders the focused creation form as a PanelsUI sheet' do
      get new_admin_hotel_path, headers: { "Turbo-Frame" => "admin_hotel_action_sheet" }

      document = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(document.at_css("turbo-frame#admin_hotel_action_sheet dialog#create-hotel-sheet")).to be_present
      expect(document.css(".panel-form-field").size).to eq(7)
      expect(document.at_css(".panel-radio-group")).to be_present
      expect(document.css(".panel-select-menu").size).to eq(3)
      expect(response.body).to include("Create only", "Create & onboard")
      payout_switch = document.at_css("input[type='checkbox'][name='admin_hotels_create_form[hide_payout_reports]']")
      expect(payout_switch).to be_present
      expect(payout_switch["checked"]).to be_nil
      expect(response.body).not_to include("Default Password", "Property amenities", "Star rating")
    end
  end

  describe 'POST /admin/hotels' do
    let!(:plan) { create(:plan, name: "Growth #{token}") }
    let(:hotel_params) do
      {
        admin_hotels_create_form: {
          account_name: 'Luma Hospitality Group',
          owner_name: 'Hotel Owner',
          owner_email: "owner-#{token}@lumastay.test",
          hotel_name: 'Luma Stay',
          sell_mode: 'per_person',
          plan_id: plan.id,
          preferred_channel_manager: 'undecided',
          creation_action: 'create_only'
        }
      }
    end

    it 'creates a setup hotel and secure pending owner invitation without a user' do
      expect {
        post admin_hotels_path, params: hotel_params
      }.to change(Account, :count).by(1)
        .and change(User, :count).by(0)
        .and change(Hotel, :count).by(1)
        .and change(StaffInvitation, :count).by(1)
        .and change(HotelOnboardingSection, :count).by(14)

      hotel = Hotel.order(:created_at).last
      invitation = hotel.staff_invitations.last

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(hotel.account.name).to eq('Luma Hospitality Group')
      expect(hotel.status).to eq('setup')
      expect(hotel.plan).to eq(plan)
      expect(hotel.sell_mode).to eq('per_person')
      expect(invitation.email).to eq("owner-#{token}@lumastay.test")
      expect(invitation.role.slug).to eq('hotel_owner')
    end

    it 'turns boat features off when the switch is unchecked' do
      no_boat_params = hotel_params.deep_dup
      no_boat_params[:admin_hotels_create_form][:allow_boat_information] = '0'

      post admin_hotels_path, params: no_boat_params

      expect(Hotel.order(:created_at).last.allow_boat_information).to be(false)
    end

    it 'keeps boat features on when the switch is left at its default' do
      post admin_hotels_path, params: hotel_params

      expect(Hotel.order(:created_at).last.allow_boat_information).to be(true)
    end

    it 'hides payout reports when the switch is checked' do
      hidden_payout_params = hotel_params.deep_dup
      hidden_payout_params[:admin_hotels_create_form][:hide_payout_reports] = '1'

      post admin_hotels_path, params: hidden_payout_params

      expect(Hotel.order(:created_at).last.hide_payout_reports).to be(true)
    end

    it 'keeps payout reports visible when the switch is left at its default' do
      post admin_hotels_path, params: hotel_params

      expect(Hotel.order(:created_at).last.hide_payout_reports).to be(false)
    end

    it 'gives a boat-enabled hotel default meal times and a generic timetable' do
      post admin_hotels_path, params: hotel_params

      hotel = Hotel.order(:created_at).last
      expect(hotel.hotel_boat_setting.lunch_time.strftime('%H:%M')).to eq('12:00')
      expect(hotel.hotel_boat_schedules.boat_in.in_service_order.map(&:time_of_day)).to eq(%w[09:00 12:00 17:00])
      expect(hotel.hotel_boat_schedules.boat_out.in_service_order.map(&:time_of_day)).to eq(%w[10:00 13:00 18:00])
    end

    it 'queues the secure owner invitation for Create & onboard' do
      onboard_params = hotel_params.deep_dup
      onboard_params[:admin_hotels_create_form][:creation_action] = 'create_and_onboard'

      expect {
        post admin_hotels_path, params: onboard_params
      }.to have_enqueued_mail(OwnerActivationMailer, :activate)
    end

    it 'provisions a usable owner account instead of an invitation when asked to verify' do
      verified_params = hotel_params.deep_dup
      verified_params[:admin_hotels_create_form][:verify_owner_account] = '1'

      expect {
        post admin_hotels_path, params: verified_params
      }.to change(User, :count).by(1)
        .and change(StaffInvitation, :count).by(0)

      hotel = Hotel.order(:created_at).last
      owner = hotel.account.users.last

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(owner.email).to eq("owner-#{token}@lumastay.test")
      expect(owner.user_hotel_accesses.first.role.slug).to eq('hotel_owner')
    end

    it 'lets the provisioned owner sign in with the generated password' do
      verified_params = hotel_params.deep_dup
      verified_params[:admin_hotels_create_form][:verify_owner_account] = '1'
      post admin_hotels_path, params: verified_params

      password = flash[:owner_credentials]["password"]
      expect(password).to be_present

      owner = User.find_by(email: "owner-#{token}@lumastay.test")
      expect(owner.authenticate(password)).to eq(owner)
    end

    it 'does not send the owner activation email when the account is provisioned directly' do
      verified_params = hotel_params.deep_dup
      verified_params[:admin_hotels_create_form][:verify_owner_account] = '1'

      expect {
        post admin_hotels_path, params: verified_params
      }.not_to have_enqueued_mail(OwnerActivationMailer, :activate)
    end

    it 'requires the immutable charging model without creating partial records' do
      params_without_sell_mode = hotel_params.deep_dup
      params_without_sell_mode[:admin_hotels_create_form].delete(:sell_mode)

      expect {
        post admin_hotels_path, params: params_without_sell_mode
      }.not_to change(Account, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Sell mode can&#39;t be blank")
    end
  end

  describe 'GET /admin/hotels/:id' do
    let(:hotel_account) { create(:account, name: "Luma Hospitality Group #{token}", status: 'active') }
    let(:hotel) { create(:hotel, account: hotel_account, name: "Luma Stay #{token}", status: 'live') }
    let!(:owner) { create(:user, :admin, account: hotel_account, name: 'Rose Yeo', email: "rose-#{token}@luma.test") }
    let!(:banking_detail) do
      create(
        :banking_detail,
        account: hotel_account,
        account_holder_name: 'Rose Yeo',
        bank_name: 'Maybank',
        account_number: '5142 1234 5678'
      )
    end
    let!(:global_margin_rule) { create(:margin_rule, settable: nil, rate: 12.0, status: 'active') }
    let!(:staff) { create(:user, account: hotel_account, name: 'Ken Tan', email: "ken-#{token}@luma.test") }
    let!(:current_month_booking) do
      create(
        :booking,
        hotel: hotel,
        booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_1"),
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
        booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_2"),
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
        booking_quote: create(:booking_quote, hotel: hotel, token: "tok_#{token}_3"),
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
      expect(Nokogiri::HTML(response.body).at_css("header.panel-page-header h1").text).to include(hotel.name)
      expect(Nokogiri::HTML(response.body).at_css(".panel-page-header__description").text).to eq("Review hotel details, account ownership, and current operating performance before taking action.")
      expect(response.body).to include('Review hotel details, account ownership, and current operating performance before taking action.')
      expect(response.body).to include('Suspend')
      expect(response.body).not_to include('Suspend Hotel')
      expect(response.body).to include('Account Information')
      expect(response.body).to include('Luma Hospitality Group')
      expect(response.body).to include('Active')
      expect(response.body).to include('Account Users')
      expect(response.body).to include('Rose Yeo')
      expect(response.body).to include("rose-#{token}@luma.test")
      expect(response.body).to include('Admin')
      expect(response.body).to include('Ken Tan')
      expect(response.body).to include("ken-#{token}@luma.test")
      expect(response.body).to include('Hotel Staff')
      expect(response.body).to include('Banking Details')
      expect(response.body).to include('Rose Yeo')
      expect(response.body).to include('Maybank')
      expect(response.body).to include('5142 1234 5678')
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
    let(:edit_hotel_account) { create(:account, name: "Edit Hotel #{token}") }
    let(:hotel) { create(:hotel, account: edit_hotel_account, status: 'live', name: "Urielle Preston #{token}") }

    it 'shows the redesigned hotel edit workspace and keeps cancel on the details page' do
      get edit_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Edit Hotel Details')
      expect(Nokogiri::HTML(response.body).at_css("header.panel-page-header h1").text).to eq("Edit Hotel Details")
      expect(Nokogiri::HTML(response.body).at_css(".panel-page-header__description").text).to eq("Manage profile information for #{hotel.name} and return to the hotel detail workspace when you are done.")
      expect(response.body).to include("Manage profile information for #{hotel.name} and return to the hotel detail workspace when you are done.")
      expect(response.body).to include('Property Profile')
      expect(response.body).to include('class="text-lg font-bold tracking-tight text-foreground sm:text-xl">Property Profile')
      expect(response.body).not_to include('Operational Notes')
      expect(response.body).to include(%(href="#{admin_hotel_path(hotel)}"))
      expect(response.body).to include('Cancel')
      expect(response.body).not_to include('Status')
      expect(response.body).not_to include('hotel[status]')
      expect(response.body).to include('Sells per room')
      expect(response.body).to include('cannot be changed after the hotel is created')
      expect(Nokogiri::HTML(response.body).at_css("[name='hotel[sell_mode]']")).to be_nil
    end
  end

  describe 'POST /admin/hotels/:id/suspend' do
    let(:suspend_account) { create(:account, name: "Suspend Hotel #{token}", status: 'active') }
    let(:hotel) { create(:hotel, account: suspend_account, status: 'live') }

    it 'suspends both the hotel and its account' do
      post suspend_admin_hotel_path(hotel)

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(flash[:notice]).to eq('Account and hotel have been suspended.')
      expect(hotel.reload.status).to eq('suspended')
      expect(suspend_account.reload.status).to eq('suspended')
    end
  end

  describe 'POST /admin/hotels/:id/approve' do
    let(:approve_account) { create(:account, name: "Approve Hotel #{token}", status: 'suspended') }
    let(:hotel) { create(:hotel, account: approve_account, status: 'suspended') }

    it 'reactivates both the hotel and its account' do
      post approve_admin_hotel_path(hotel)

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(flash[:notice]).to eq('Account and hotel have been reactivated.')
      expect(hotel.reload.status).to eq('live')
      expect(approve_account.reload.status).to eq('active')
    end
  end

  describe 'GET /admin/hotels/:id/edit' do
    let(:hotel) { create(:hotel, hide_payout_reports: true) }

    it 'renders the checked payout reports switch' do
      get edit_admin_hotel_path(hotel)

      document = Nokogiri::HTML(response.body)
      payout_switch = document.at_css("input[type='checkbox'][name='hotel[hide_payout_reports]']")

      expect(response).to have_http_status(:ok)
      expect(payout_switch).to be_present
      expect(payout_switch["checked"]).to eq("checked")
    end
  end

  describe 'PATCH /admin/hotels/:id' do
    let(:hotel_account) { create(:account, name: "Luma Hospitality Group #{token}", status: 'active') }
    let(:hotel) { create(:hotel, account: hotel_account, name: "Luma Stay #{token}", status: 'setup', sell_mode: "per_room") }

    it 'refuses a tampered charging-model change and rolls back other attributes' do
      patch admin_hotel_path(hotel), params: { hotel: { name: 'Changed name', sell_mode: 'per_person' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(hotel.reload).to have_attributes(name: "Luma Stay #{token}", sell_mode: 'per_room')
    end

    it 'can hide and show payout reports' do
      patch admin_hotel_path(hotel), params: { hotel: { hide_payout_reports: '1' } }

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(hotel.reload.hide_payout_reports).to be(true)

      patch admin_hotel_path(hotel), params: { hotel: { hide_payout_reports: '0' } }

      expect(response).to redirect_to(admin_hotel_path(hotel))
      expect(hotel.reload.hide_payout_reports).to be(false)
    end
  end
end
