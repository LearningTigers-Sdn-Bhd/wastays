# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::ActionCard, type: :component do
  it "makes the whole card a labelled link with a visible focus treatment" do
    render_inline(described_class.new(label: "Report a problem", hint: "Tell the hotel team what is wrong.",
                                      icon: "circle-alert", tone: :issue, href: "/requests/new"))

    expect(page).to have_css("a.guest-action-card[href='/requests/new']", text: "Report a problem")
    expect(page).to have_css(".guest-action-card__hint", text: "Tell the hotel team what is wrong.")
    expect(page).to have_no_css(".guest-action-card a")
    expect(page).to have_css(".guest-action-card__icon[aria-hidden='true']")
    expect(page).to have_css("a.guest-action-card[data-tone='issue']")
    expect(page.find("a.guest-action-card")[:class]).to include("focus-visible:ring-2")
  end

  it "leaves out the hint when the service does not have one" do
    render_inline(described_class.new(label: "Contact the front desk", icon: "phone", tone: :contact, href: "/contact"))

    expect(page).to have_no_css(".guest-action-card__hint")
    expect(page).to have_css("a.guest-action-card[data-tone='contact']")
  end
end
