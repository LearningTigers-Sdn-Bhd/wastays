require "rails_helper"

RSpec.describe "Guest login page", type: :request do
  def document = Nokogiri::HTML(response.body)
  def navbar = document.at_css("header.guest-navbar")

  it "shows the choices, with Home on the right and no way back" do
    get guest_login_path

    expect(response).to have_http_status(:success)
    expect(document.at_css("nav.guest-bottom-nav, .guest-navbar__nav")).to be_nil
    expect(navbar.at_css(".guest-navbar__actions a[href='#{root_path}']").text.squish).to eq("Home")
    expect(navbar.at_css("a.guest-navbar__back")).to be_nil
    expect(document.css("a.guest-card__row").map { |row| row["href"] })
      .to eq([ guest_login_path(via: "whatsapp"), guest_login_path(via: "email") ])
  end

  it "shows one method with a way back to the choices" do
    get guest_login_path(via: "whatsapp")

    expect(response.body).to include("WhatsApp Login")
    expect(response.body).not_to include("Email Login")
    expect(navbar.at_css("a.guest-navbar__back")["href"]).to eq(guest_login_path)
  end

  it "shows the email form" do
    get guest_login_path(via: "email")

    expect(document.at_css("form[action='#{guest_request_magic_link_path}'] input[type='email'][name='email']")).to be_present
  end

  it "shows check your inbox after a link is sent" do
    get guest_login_path(email_sent: true)

    expect(response.body).to include("Check your inbox")
    expect(navbar.at_css("a.guest-navbar__back")["href"]).to eq(guest_login_path)
  end

  it "comes back on the email panel with the error when the email is unknown" do
    post guest_request_magic_link_path, params: { email: "nobody@example.com" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css(".guest-notice[role='alert']").text).to include("No account found for that email.")
    expect(document.at_css("input[name='email']")["value"]).to eq("nobody@example.com")
  end
end
