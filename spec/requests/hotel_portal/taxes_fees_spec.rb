require "rails_helper"

RSpec.describe "HotelPortal::TaxesFees", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "setup", tourism_tax_enabled: true, tourism_tax_amount: 10.0, sst_enabled: true) }
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

  describe "GET /hotel/:hotel_id/settings/finance/taxes-and-fees" do
    it "renders one normalized registry table with system taxes first" do
      HotelTax.create!(hotel: hotel, name: "Heritage Fee", code: "HF", charge_type: "tax", rate_type: "flat", amount: 2.0, enabled: false)
      HotelTax.create!(hotel: hotel, name: "Service Charge", code: "SC", charge_type: "charge", rate_type: "percentage", amount: 10.0, enabled: true)

      get hotel_taxes_fees_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Taxes & Fees" ])
      expect(document.css("table.panel-table[data-testid='taxes-fees-registry'][data-striped='true']").count).to eq(1)
      expect(document.at_css("table[data-testid='taxes-fees-registry']")&.parent&.classes).to include(
        "panel-table__wrapper", "rounded-md", "border", "border-border"
      )
      expect(document.css("[data-testid='taxes-fees-registry'] th").map { |heading| heading.text.squish }).to eq(
        [ "Status", "Charge", "Code", "Applies To", "Charge Rule", "Charge Amount", "Action" ]
      )
      expect(document.css("[data-testid='taxes-fees-registry'] tbody tr").map { |row| row["id"] }).to eq(
        [ "tax-registry-row-sst", "tax-registry-row-tourism_tax", "tax-registry-row-hotel_tax_#{hotel.hotel_taxes.find_by!(name: 'Heritage Fee').id}", "tax-registry-row-hotel_tax_#{hotel.hotel_taxes.find_by!(name: 'Service Charge').id}" ]
      )
      expect(response.body).to include("Service Tax (SST)", "TAX_SST", "8.00%")
      expect(response.body).to include("Tourism Tax (TTx)", "TAX_TTX", "RM 10.00 / room / night")
      expect(response.body).to include("Heritage Fee", "TAX_HF", "Service Charge", "SC")
      expect(response.body).not_to include("Primary Tax Settings", "Additional Taxes &amp; Fees")
      expect(document.css("[data-testid='taxes-fees-registry'] tbody a[data-turbo-frame='settings_action_sheet']").count).to eq(4)
      expect(document.at_css("turbo-frame#settings_action_sheet")).to be_present
    end

    it "uses Registry by default and supports a URL-synced reference tab" do
      get hotel_taxes_fees_path(hotel, tab: "malaysia_reference")

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.at_css("#taxes-fees-tabs-tab-malaysia_reference") ["aria-selected"]).to eq("true")
      expect(document.at_css("#malaysia-reference-panel")).not_to have_attribute("hidden")
      expect(response.body).to include("Content last updated: 12 July 2026")
      expect(response.body).to include("Always verify current rates with the relevant state authority")
    end

    it "falls back to Registry for an unsupported tab" do
      get hotel_taxes_fees_path(hotel, tab: "unsupported")

      document = response.parsed_body
      expect(document.at_css("#taxes-fees-tabs-tab-registry")["aria-selected"]).to eq("true")
      expect(document.at_css("#registry-panel")).not_to have_attribute("hidden")
    end
  end

  describe "system tax action sheets" do
    it "renders SST as a mostly read-only management sheet" do
      get hotel_edit_system_tax_path(hotel, "sst"), headers: { "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.at_css("turbo-frame#settings_action_sheet dialog#manage-sst-sheet")).to be_present
      expect(response.body).to include("Service Tax (SST)", "TAX_SST", "All guests", "Room charge", "8.00%")
      expect(document.at_css("input[name='hotel[sst_enabled]']")).to be_present
      expect(document.at_css("input[name='hotel[tourism_tax_amount]']")).to be_nil
      expect(response.body).to include("system-defined and cannot be changed")
    end

    it "renders TTx with editable status and amount" do
      get hotel_edit_system_tax_path(hotel, "tourism_tax"), headers: { "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.at_css("turbo-frame#settings_action_sheet dialog#manage-tourism-tax-sheet")).to be_present
      expect(response.body).to include("Tourism Tax (TTx)", "TAX_TTX", "Foreign guests only", "Per room / night")
      expect(document.at_css("input[name='hotel[tourism_tax_enabled]']")).to be_present
      expect(document.at_css("input[name='hotel[tourism_tax_amount]'][value='10.0']")).to be_present
    end

    it "rejects unknown system tax keys" do
      get hotel_edit_system_tax_path(hotel, "unknown"), headers: { "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end

    it "updates a system tax through sheet completion and synchronizes its transaction code" do
      patch hotel_system_tax_path(hotel, "sst"),
        params: { hotel: { sst_enabled: "0" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="complete_sheet"', 'target="settings_action_sheet"', "tab=registry")
      expect(hotel.reload.sst_enabled?).to be(false)
      expect(hotel.transaction_codes.find_by!(system_key: "sst_tax")).not_to be_active
    end

    it "updates a registry status with a normal redirect" do
      patch hotel_system_tax_path(hotel, "tourism_tax"), params: {
        registry_status: "1",
        hotel: { tourism_tax_enabled: "0" }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel, tab: "registry"))
      expect(hotel.reload.tourism_tax_enabled?).to be(false)
    end

    it "does not accept TTx fields through the SST endpoint" do
      patch hotel_system_tax_path(hotel, "sst"), params: {
        registry_status: "1",
        hotel: { sst_enabled: "0", tourism_tax_amount: "99.00" }
      }

      expect(hotel.reload.tourism_tax_amount).to eq(10.0)
    end
  end

  describe "custom tax and fee action sheets" do
    it "renders the add sheet with Tax and Fee staff-facing choices" do
      get new_hotel_hotel_tax_path(hotel), headers: { "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.at_css("turbo-frame#settings_action_sheet dialog#add-hotel-tax-sheet")).to be_present
      expect(document.css("select[name='hotel_tax[charge_type]'] option").map(&:text)).to include("Tax", "Fee")
      expect(document.at_css("[data-tax-code-field-target~='chargeType']")).to be_present
      expect(document.at_css(".panel-control-group [data-tax-code-field-target~='prefix']")&.text).to eq("TAX_")
      expect(document.at_css("[data-tax-code-field-target~='help']")&.text).to include("Saved as TAX_DBKK")
      expect(document.css("form .grid.items-start").count).to eq(2)
      expect(response.body).not_to include("offcanvas_drawer", ">Others<", ">Charge<")
      expect(response.body).to include("Name", "Code", "Applies To", "Charge Rule", "Charge Amount", "Active")
    end

    it "renders legacy others records as Fee without changing their stored value" do
      fee = HotelTax.create!(hotel: hotel, name: "Legacy Fee", code: "LEG", charge_type: "others", rate_type: "flat", amount: 3.0)

      get edit_hotel_hotel_tax_path(hotel, fee), headers: { "Turbo-Frame" => "settings_action_sheet" }

      document = response.parsed_body
      selected = document.at_css("select[name='hotel_tax[charge_type]'] option[selected]")
      expect(selected.text).to eq("Fee")
      expect(selected["value"]).to eq("others")
      expect(fee.reload.charge_type).to eq("others")
    end

    it "creates a new Fee with the internal charge type and unprefixed transaction code" do
      expect {
        post hotel_hotel_taxes_path(hotel), params: {
          hotel_tax: {
            name: "Service Charge",
            code: "SC",
            charge_type: "charge",
            rate_type: "percentage",
            amount: "10.00",
            enabled: "1",
            foreign_guests_only: "false"
          }
        }
      }.to change { hotel.hotel_taxes.count }.by(1)

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel, tab: "registry"))
      fee = hotel.hotel_taxes.find_by!(name: "Service Charge")
      expect(fee).to have_attributes(charge_type: "charge", foreign_guests_only: false)
      expect(fee.transaction_code).to have_attributes(code: "SC", kind: "charge", active: true)
    end

    it "creates a Tax with the generated prefix through Turbo sheet completion" do
      post hotel_hotel_taxes_path(hotel),
        params: {
          hotel_tax: {
            name: "Heritage Fee",
            code: "DBKK",
            charge_type: "tax",
            rate_type: "flat",
            amount: "5.00",
            enabled: "1",
            foreign_guests_only: "false"
          }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" }

      expect(response.body).to include('action="complete_sheet"', 'target="settings_action_sheet"', "tab=registry")
      expect(hotel.hotel_taxes.find_by!(name: "Heritage Fee").transaction_code.code).to eq("TAX_DBKK")
    end

    it "keeps validation errors inside the add sheet" do
      post hotel_hotel_taxes_path(hotel),
        params: { hotel_tax: { name: "", code: "", charge_type: "tax", rate_type: "flat", amount: "0" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css("turbo-frame#settings_action_sheet dialog#add-hotel-tax-sheet")).to be_present
      expect(response.body).to include("can&#39;t be blank", "must be greater than 0")
    end

    it "updates only status from the registry and synchronizes the generated code" do
      tax = HotelTax.create!(hotel: hotel, name: "Heritage Fee", code: "HF", charge_type: "tax", rate_type: "flat", amount: 2.0, enabled: true)

      patch hotel_hotel_tax_path(hotel, tax), params: { registry_status: "1", hotel_tax: { enabled: "0" } }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel, tab: "registry"))
      expect(tax.reload.enabled?).to be(false)
      expect(tax.transaction_code.reload.active?).to be(false)
      expect(tax).to have_attributes(name: "Heritage Fee", amount: 2.0)
    end

    it "scopes custom records to the current hotel" do
      other_hotel = create(:hotel, account: account)
      other_tax = HotelTax.create!(hotel: other_hotel, name: "Other Hotel Fee", code: "OHF", rate_type: "flat", amount: 2.0)

      get edit_hotel_hotel_tax_path(hotel, other_tax), headers: { "Turbo-Frame" => "settings_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
