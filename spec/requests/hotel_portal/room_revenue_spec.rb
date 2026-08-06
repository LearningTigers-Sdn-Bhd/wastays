require "rails_helper"

RSpec.describe "HotelPortal::RoomRevenue", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered", sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10) }
  let!(:service_charge) { create(:hotel_tax, hotel: hotel, name: "Service Charge", rate_type: "percentage", amount: 10.0) }
  let!(:inactive_fee) { create(:hotel_tax, hotel: hotel, name: "Inactive Levy", rate_type: "flat", amount: 2.0, enabled: false) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:manage_profile_permission) do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
  end

  before do
    RolePermission.find_or_create_by!(role: role, permission: manage_profile_permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def room_code
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    hotel.transaction_codes.find_by!(system_key: "room_revenue")
  end

  def preview_tax_rules(keys)
    patch hotel_preview_room_revenue_tax_rules_path(hotel), params: { transaction_code: { tax_rule_keys: keys } }
  end

  def confirm_tax_rules(keys, reason: "Approved hotel tax policy")
    token = Nokogiri::HTML(response.body).at_css("input[name='freshness_token']")["value"]
    patch hotel_room_revenue_tax_rules_path(hotel), params: {
      transaction_code: { tax_rule_keys: keys },
      confirm_hotel_tax_rules: "1",
      freshness_token: token,
      reason: reason
    }
  end

  def create_open_room_forecast
    room_type = create(:room_type, hotel: hotel)
    booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day)
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 123.45)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_forecasted_charge, booking_folio: folio, amount: 123.45)
  end

  describe "GET /settings/commercial/room-revenue" do
    it "renders both tabs, the tax rules, the posting preview and the seeded policies" do
      get hotel_room_revenue_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Room Revenue", "Tax rules", "Reservation policies")
      expect(response.body).to include("SST 8%", "Tourism Tax", "Service Charge", "Inactive Levy")
      expect(response.body).to include("Posting preview", "Apply changes to")
      expect(response.body).to include("New bookings only")
      expect(response.body).to include("Late checkout", "Early departure", "No show", "Cancellation")
      expect(hotel.hotel_reservation_policies.count).to eq(4)
    end

    it "uses the line tab variant, not pill" do
      get hotel_room_revenue_path(hotel)

      expect(response.body).to include("tabs-root--line")
      expect(response.body).not_to include("tabs-root--pill")
    end

    it "does not offer transaction code creation" do
      get hotel_room_revenue_path(hotel)

      expect(response.body).not_to include("New Code")
    end
  end

  describe "legacy URLs" do
    it "redirects the retired finance transaction codes page" do
      get "/hotel/#{hotel.to_param}/settings/finance/transaction-codes"

      expect(response).to redirect_to("/hotel/#{hotel.to_param}/settings/commercial/room-revenue")
    end

    it "redirects the older top-level transaction codes bookmarks" do
      get "/hotel/#{hotel.to_param}/transaction-codes"
      expect(response).to redirect_to("/hotel/#{hotel.to_param}/settings/commercial/room-revenue")

      get "/hotel/#{hotel.to_param}/transaction-codes/new"
      expect(response).to redirect_to("/hotel/#{hotel.to_param}/settings/commercial/room-revenue")

      get "/hotel/#{hotel.to_param}/transaction-codes/1/edit"
      expect(response).to redirect_to("/hotel/#{hotel.to_param}/settings/commercial/room-revenue")
    end
  end

  describe "PATCH room-revenue/configuration" do
    it "creates and updates the hotel transaction configuration" do
      expect {
        patch hotel_room_revenue_configuration_path(hotel), params: {
          hotel_transaction_configuration: { room_revenue_tax_rule_application: "open_folio_forecasts" }
        }
      }.to change { HotelTransactionConfiguration.where(hotel: hotel).count }.from(0).to(1)

      expect(response).to redirect_to(hotel_room_revenue_path(hotel))
      expect(hotel.reload.transaction_configuration.room_revenue_tax_rule_application).to eq("open_folio_forecasts")
    end

    it "refreshes open folio forecasts when the open folio option is saved" do
      allow(Folios::Forecasts::RefreshOpenForecastsFromRoomRevenueRules).to receive(:call)

      patch hotel_room_revenue_configuration_path(hotel), params: {
        hotel_transaction_configuration: { room_revenue_tax_rule_application: "open_folio_forecasts" }
      }

      expect(Folios::Forecasts::RefreshOpenForecastsFromRoomRevenueRules).to have_received(:call).with(hotel: hotel, actor: user)
    end
  end

  describe "PATCH room-revenue/tax-rules" do
    it "saves without an interstitial when no forecasts are impacted" do
      code = room_code

      preview_tax_rules([ "primary:sst_tax", "hotel_tax:#{service_charge.id}" ])

      expect(response).to redirect_to(hotel_room_revenue_path(hotel))
      expect(code.reload.tax_rule_keys).to match_array([ "primary:sst_tax", "hotel_tax:#{service_charge.id}" ])
      expect(code).to be_is_taxable
    end

    it "clears taxable when every rule is removed" do
      code = room_code
      code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      code.update!(is_taxable: true)

      preview_tax_rules([])

      expect(code.reload.tax_rule_keys).to be_empty
      expect(code).not_to be_is_taxable
    end

    it "reviews and confirms a change when open forecasts are impacted" do
      hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
      create_open_room_forecast
      code = room_code

      preview_tax_rules([ "primary:sst_tax" ])
      expect(response.body).to include("Change hotel default?")
      expect(code.reload.tax_rule_keys).to be_empty

      confirm_tax_rules([ "primary:sst_tax" ])

      expect(response).to redirect_to(hotel_room_revenue_path(hotel))
      expect(code.reload.tax_rule_keys).to match_array([ "primary:sst_tax" ])
      audit = FinancialAuditEvent.find_by!(event_type: "hotel_tax_rules_changed", hotel: hotel)
      expect(audit).to have_attributes(actor: user, reason: "Approved hotel tax policy")
      expect(audit.metadata).to include("transaction_code" => "ROOM", "before_tax_rule_keys" => [])
    end

    it "blocks a direct unconfirmed change when open forecasts are impacted" do
      hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
      create_open_room_forecast
      code = room_code

      patch hotel_room_revenue_tax_rules_path(hotel), params: { transaction_code: { tax_rule_keys: [ "primary:sst_tax" ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Review and confirm hotel-wide tax inclusion changes")
      expect(code.reload.tax_rule_keys).to be_empty
    end

    it "rejects confirmation without a reason" do
      hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
      create_open_room_forecast
      code = room_code
      preview_tax_rules([ "primary:sst_tax" ])

      confirm_tax_rules([ "primary:sst_tax" ], reason: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Reason is required")
      expect(code.reload.tax_rule_keys).to be_empty
    end

    it "rejects a stale confirmation" do
      hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
      create_open_room_forecast
      code = room_code
      preview_tax_rules([ "primary:sst_tax" ])
      code.touch

      confirm_tax_rules([ "primary:sst_tax" ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("changed after this review")
      expect(code.reload.tax_rule_keys).to be_empty
    end

    it "rejects a tax belonging to another hotel" do
      code = room_code
      foreign_tax = create(:hotel_tax)

      preview_tax_rules([ "hotel_tax:#{foreign_tax.id}" ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("unavailable for this hotel")
      expect(code.reload.tax_rule_keys).to be_empty
    end

    it "does not change posted transactions" do
      code = room_code
      transaction = create(:folio_transaction, transaction_code: code, category: code.category)
      original_attributes = transaction.attributes

      preview_tax_rules([ "primary:sst_tax" ])

      expect(transaction.reload.attributes).to eq(original_attributes)
    end

    it "requires manage hotel profile permission" do
      code = room_code
      RolePermission.where(role: role, permission: manage_profile_permission).delete_all

      preview_tax_rules([ "primary:sst_tax" ])

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(code.reload.tax_rule_keys).to be_empty
    end
  end
end
