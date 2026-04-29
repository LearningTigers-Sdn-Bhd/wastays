require "rails_helper"

RSpec.describe "Legal pages", type: :system do
  before do
    driven_by(:selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ])
  end

  it "clears the landing loader scroll lock after navigating from home to the privacy policy" do
    visit root_path
    visit privacy_policy_path

    expect(page).to have_current_path(privacy_policy_path, ignore_query: true)
    expect(page.evaluate_script("document.documentElement.classList.contains('landing-loader-active')")).to be(false)
  end
end
