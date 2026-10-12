require "rails_helper"

RSpec.describe "HotelPortal::CorporateAccountAdditions", type: :request do
  let(:hotel) { create(:hotel) }
  let(:staff) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:headers) { { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "external_account_sheet" } }

  before do
    role.permissions << (Permission.find_by(slug: "manage_corporate_accounts") || create(:permission, slug: "manage_corporate_accounts"))
    create(:user_hotel_access, user: staff, hotel: hotel, role: role)
    sign_in_as(staff)
  end

  it "opens a separate email-first sheet" do
    get new_hotel_corporate_account_addition_path(hotel), headers: headers
    expect(response.body).to include("Add account", "Login email", "Continue")
    expect(response.body).not_to include("Company name", "Credit limit")
  end

  it "looks up a new email without writes and prefills direct bill with the hotel currency" do
    expect {
      post lookup_hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: { email: "new@example.com" } }, headers: headers
    }.not_to change(User, :count)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Company name", "Contact person", "Credit limit")
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[type="radio"][value="direct_bill"]')["checked"]).to be_present
    expect(doc.at_css('select[name$="[credit_currency]"] option[selected]')["value"]).to eq(hotel.default_currency)
    expect(doc.at_css('[data-corporate-billing-terms-target="terms"]')["hidden"]).to be_nil
  end

  it "shows existing company identity without asking for replacement details" do
    corporate_user = create(:user, :corporate)
    post lookup_hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: { email: corporate_user.email } }, headers: headers
    expect(response.body).to include(CGI.escapeHTML(corporate_user.account.name))
    expect(response.body).not_to include('name="corporate_account_addition[account_name]"')
  end

  it "creates a new login and shows credentials without sending an invitation" do
    expect {
      post hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: {
        email: "new@example.com", account_name: "New Agency", name: "Contact", relationship_type: "direct_bill"
      } }, headers: headers
    }.not_to have_enqueued_mail(CorporateInvitationMailer, :invite)
    user = User.find_by!(email: "new@example.com")
    expect(response.body).to include(user.temporary_password, "Temporary sign-in details", 'target="external_account_sheet"')
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "links an existing login and returns to the filtered list" do
    corporate_user = create(:user, :corporate)
    destination = hotel_corporate_accounts_path(hotel, account_type: "travel_agent")
    post hotel_corporate_account_addition_path(hotel), params: { return_to: destination,
      corporate_account_addition: { email: corporate_user.email, account_type: "travel_agent" } }, headers: headers
    expect(response.body).to include('action="complete_sheet"', destination)
    expect(hotel.hotel_corporate_accounts.last.corporate_account).to eq(corporate_user.account)
    expect(response.body).not_to include("Temporary sign-in details")
  end

  it "preserves an explicit Standard selection and typed values after a failed save" do
    post hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: {
      email: "new@example.com", account_name: "Typed Name", name: "", relationship_type: "standard"
    } }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Typed Name")
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[type="radio"][value="standard"]')["checked"]).to be_present
  end

  it "requires account-management permission for lookup and creation" do
    role.permissions.clear
    post lookup_hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: { email: "new@example.com" } }
    expect(response).to have_http_status(:redirect)
    expect {
      post hotel_corporate_account_addition_path(hotel), params: { corporate_account_addition: { email: "new@example.com", account_name: "Agency", name: "Contact" } }
    }.not_to change(User, :count)
  end
end
