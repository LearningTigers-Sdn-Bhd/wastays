module SystemAuthHelper
  def sign_in_through_ui(user, password: "password123")
    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: password
    click_button "Sign In to Portal"

    expect(page).to have_no_current_path(login_path, wait: 10)
    expect(page).to have_css("body", wait: 10)
    return unless js_driver?

    page.document.synchronize do
      raise Capybara::ElementNotFound, "page still loading after sign in" unless page.evaluate_script("document.readyState") == "complete"
    end
  end

  def js_driver?
    Capybara.current_driver != :rack_test
  end

  def visit_when_loaded(path)
    visit(path)
  rescue Ferrum::PendingConnectionsError
    raise unless current_url_matches?(path)

    expect(page).to have_css("body", wait: 10)
  end

  def current_url_matches?(path)
    expected = URI.parse(path)
    current = URI.parse(page.current_url)
    current.path == expected.path && Rack::Utils.parse_nested_query(current.query) == Rack::Utils.parse_nested_query(expected.query)
  rescue URI::InvalidURIError, Ferrum::Error
    false
  end
end

RSpec.configure do |config|
  config.include SystemAuthHelper, type: :system
end
