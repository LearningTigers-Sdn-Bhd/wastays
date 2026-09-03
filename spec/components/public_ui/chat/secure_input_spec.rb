require "rails_helper"

RSpec.describe PublicUI::Chat::SecureInput, type: :component do
  it "renders an uppercase confirmation-code field" do
    render_inline(described_class.new(url: "/booking", kind: :confirmation_code))

    expect(page).to have_field("Booking confirmation code")
    expect(page).to have_css("input[name='confirmation_token'][maxlength='64']")
    expect(page).to have_css("form[action='/booking']")
  end
end
