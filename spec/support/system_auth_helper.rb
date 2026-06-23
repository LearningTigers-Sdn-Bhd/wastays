module SystemAuthHelper
  def sign_in_through_ui(user, password: "password123")
    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: password
    click_button "Sign In to Portal"

    expect(page).to have_no_current_path(login_path, wait: 10)
  end
end

RSpec.configure do |config|
  config.include SystemAuthHelper, type: :system
end
