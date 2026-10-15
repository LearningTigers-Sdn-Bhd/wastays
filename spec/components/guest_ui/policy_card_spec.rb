# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::PolicyCard, type: :component do
  it "turns each line staff wrote into a rule" do
    render_inline(described_class.new(title: "House Rules", icon: "house",
                                      body: "Quiet hours are 10 PM to 7 AM.\n\n- No smoking in rooms.\n"))

    expect(page).to have_css("article.guest-policy h3", text: "House Rules")
    expect(page).to have_css(".guest-guide-icon svg[aria-hidden='true']")
    expect(page).to have_css("ul.guest-policy__rules li", count: 2)
    expect(page).to have_css("li", text: /\ANo smoking in rooms\.\z/)
  end

  it "keeps a one-line policy as a sentence" do
    render_inline(described_class.new(title: "Pets", body: "Pets are not allowed."))

    expect(page).to have_no_css("ul")
    expect(page).to have_css("p.guest-policy__text", text: "Pets are not allowed.")
  end

  it "shows each change with its charge and note" do
    render_inline(described_class.new(title: "Changes", terms: [ [ "Late checkout", "MYR 100", "Ask the day before." ] ]))

    expect(page).to have_css(".guest-policy__term dt", text: "Late checkout")
    expect(page).to have_css(".guest-policy__term-value", text: "MYR 100")
    expect(page).to have_css(".guest-policy__term-note", text: "Ask the day before.")
  end

  it "draws nothing without rules or terms" do
    render_inline(described_class.new(title: "Empty", body: "  \n"))

    expect(page).to have_no_css("article")
  end
end
