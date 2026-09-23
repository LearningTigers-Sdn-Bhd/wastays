require "rails_helper"

RSpec.describe "Guest login page", type: :request do
  def document = Nokogiri::HTML(response.body)

  it "renders the sign-in choices in the portal layout, without the portal navigation" do
    get guest_login_path

    expect(response).to have_http_status(:success)
    expect(document.at_css("body .guest-portal main.guest-portal__main")).to be_present
    expect(document.at_css("header.guest-navbar, nav.guest-bottom-nav")).to be_nil

    root = document.at_css("[data-controller='guest-login']")
    expect(root["data-guest-login-is-error-value"]).to eq("false")
    %w[choice whatsapp email emailSuccess].each do |target|
      expect(root.at_css("[data-guest-login-target='#{target}']")).to be_present
    end
    expect(root.css("button[data-action^='click->guest-login#show']").map { |button| button.text.squish })
      .to include("Continue with WhatsApp Get a sign-in link on WhatsApp", "Continue with Email Get a sign-in link in your inbox")
    expect(root.at_css("form[action='#{guest_request_magic_link_path}'] input[type='email'][name='email']")).to be_present
  end

  it "shows the error and opens the email panel when the email is unknown" do
    post guest_request_magic_link_path, params: { email: "nobody@example.com" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css(".guest-notice[role='alert']").text).to include("No account found for that email.")
    expect(document.at_css("[data-controller='guest-login']")["data-guest-login-is-error-value"]).to eq("true")
    expect(document.at_css("input[name='email']")["value"]).to eq("nobody@example.com")
  end
end
